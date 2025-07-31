import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, regexp_replace

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'source-bucket', 'target-bucket', 'triggered-by-file'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read Parquet from S3
source_path = f"s3://{args['source-bucket']}/{args['triggered-by-file']}"
df = spark.read.parquet(source_path)

# Log schema
print("Input DataFrame Schema:")
df.printSchema()

# Clean 'Qtde. Teórica' by removing dots and casting to bigint
df = df.withColumn("Qtde. Teórica", regexp_replace(col("Qtde. Teórica"), "\\.", "").cast("bigint"))

# Log sample after cleaning
print("Input DataFrame Sample (5 rows):")
df.show(5)

# Filter valid 'Tipo' values
valid_tipos = ['ON', 'PN', 'PNA', 'UNT', 'PNB']
df_filtered = df.filter(col("Tipo").isin(valid_tipos))

# Log filtered results
print("Unique 'Tipo' values after filtering:")
df_filtered.select("Tipo").distinct().show()
print(f"Filtered DataFrame row count: {df_filtered.count()}")

# Write partitioned output
output_path = f"s3://{args['target-bucket']}/refined/"
df_filtered.write \
    .mode("overwrite") \
    .partitionBy("Tipo") \
    .parquet(output_path)

# Aggregate and log counts per Tipo
df_agg = df_filtered.groupBy("Tipo").count()
print("Aggregated DataFrame (counts per Tipo):")
df_agg.show()

job.commit()