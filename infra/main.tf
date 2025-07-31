provider "aws" {
  region = var.aws_region
}

# S3 Bucket configurável
resource "aws_s3_bucket" "b3_glue" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name        = "B3 Glue Data"
    Environment = var.environment
    Security    = "Private"
  }
}

# Habilitar versionamento para proteção de dados
resource "aws_s3_bucket_versioning" "b3_glue_versioning" {
  bucket = aws_s3_bucket.b3_glue.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload the Glue visual job script inline via Terraform
resource "aws_s3_object" "glue_visual_script" {
  bucket  = aws_s3_bucket.b3_glue.id
  key     = "scripts/b3-visual-etl.py"
  content = <<EOT
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, current_date, datediff, to_date, regexp_replace, countDistinct, input_file_name

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from S3 raw with partition inference
source_path = "s3://fiap-2025-tech02-b3-glue-119268833495/raw/"
spark_df = spark.read.option("basePath", source_path).parquet(f"{source_path}dt_particao=*/")
spark_df = spark_df.withColumn("dt_particao", regexp_replace(input_file_name(), ".*/dt_particao=(\\d+)/.*", "$1"))

# Filter valid Tipo
valid_tipos = ['ON', 'PN', 'PNA', 'PNB', 'UNT']
spark_df = spark_df.filter(col("Tipo").isin(valid_tipos))

# Rename two columns (requirement 5)
spark_df = spark_df.withColumnRenamed("Código", "codigo") \
                   .withColumnRenamed("Ação", "acao")

# Clean Qtde. Teórica
spark_df = spark_df.withColumn("qtde_teorica", regexp_replace(col("`Qtde. Teórica`"), "\\.", "").cast("bigint"))

# Date calculation (requirement 5)
spark_df = spark_df.withColumn("dias_desde_pregao", datediff(current_date(), to_date("dt_particao", "yyyyMMdd")))

# Aggregation (requirement 5: numeric summarization)
agg_df = spark_df.groupBy("Tipo").agg(countDistinct("acao").alias("num_acoes"))
agg_df.write.mode("overwrite").parquet("s3://fiap-2025-tech02-b3-glue-119268833495/temp/agg/")

# Write refined data (requirement 6)
spark_df.write.mode("append") \
        .partitionBy("dt_particao", "codigo") \
        .parquet("s3://fiap-2025-tech02-b3-glue-119268833495/refined/")

# Catalog the table (requirement 7)
spark.sql("""
CREATE EXTERNAL TABLE IF NOT EXISTS b3_database.b3_refined (
  acao STRING,
  Tipo STRING,
  qtde_teorica BIGINT,
  `Part. (%)` DOUBLE,
  dias_desde_pregao INT
)
PARTITIONED BY (dt_particao STRING, codigo STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION 's3://fiap-2025-tech02-b3-glue-119268833495/refined/'
""")
spark.sql("MSCK REPAIR TABLE b3_database.b3_refined")

job.commit()
EOT

  tags = {
    Name = "B3 Visual ETL Script"
  }
}

# Create ZIP for Lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/glue_trigger.zip"

  source {
    content  = <<EOT
import json
import os
import boto3

client = boto3.client('glue')

def start_glue_job(job_name):
    job = client.start_job_run(JobName=job_name)
    status = client.get_job_run(JobName=job_name, RunId=job['JobRunId'])
    return status['JobRun']['JobRunState']

def lambda_handler(event, context):
    job_name = os.environ.get("JOB_NAME", None)
    file_name = event['Records'][0]['s3']['object']['key']

    print(f"Lambda triggered with the addition of file {file_name}")

    if job_name is None:
        raise Exception("JOB_NAME is not set")
    else:
        try:
            status = start_glue_job(job_name)
            print(f"Job status: {status}")
        except Exception as e:
            print(f"Error running job: {e}")
            raise e

    return {
        'statusCode': 200,
        'body': json.dumps(f'Glue Job {job_name} Started')
    }
EOT
    filename = "lambda_function.py"
  }
}

# Upload Lambda ZIP
resource "aws_s3_object" "lambda_trigger_script" {
  bucket  = aws_s3_bucket.b3_glue.id
  key     = "scripts/glue_trigger.zip"
  source  = data.archive_file.lambda_zip.output_path
  etag    = filemd5(data.archive_file.lambda_zip.output_path)

  tags = {
    Name = "B3 Lambda Trigger Code"
  }
}

# Configuração de notificação S3 para Lambda
resource "aws_s3_bucket_notification" "b3_lambda_trigger" {
  bucket = aws_s3_bucket.b3_glue.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.glue_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".parquet"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Função Lambda para trigger do Glue
resource "aws_lambda_function" "glue_trigger" {
  s3_bucket        = aws_s3_bucket.b3_glue.bucket
  s3_key           = "scripts/glue_trigger.zip"
  function_name    = "b3-glue-trigger"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      JOB_NAME = local.visual_job_name
    }
  }

  tags = {
    Name        = "B3 Glue Trigger"
    Environment = var.environment
  }

  depends_on = [aws_s3_object.lambda_trigger_script]
}

# Permissão para S3 invocar Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.glue_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.b3_glue.arn
}

# Glue Database
resource "aws_glue_catalog_database" "b3_database" {
  name = "b3_database"
}

# Glue Job
resource "aws_glue_job" "b3_visual_etl" {
  name     = "b3-visual-etl"
  role_arn = aws_iam_role.lambda_glue_role.arn
  command {
    script_location = "s3://${aws_s3_bucket.b3_glue.bucket}/scripts/b3-visual-etl.py"
    name            = "glueetl"
  }
  default_arguments = {
    "--source-bucket"         = "fiap-2025-tech02-b3-glue-119268833495"
    "--target-bucket"         = "fiap-2025-tech02-b3-glue-119268833495"
    "--TempDir"               = "s3://fiap-2025-tech02-b3-glue-119268833495/temp/"
    "--job-bookmark-option"   = "job-bookmark-enable"
    "--enable-metrics"        = "true"
    "--enable-spark-ui"       = "true"
    "--enable-glue-datacatalog" = "true"
    "--enable-job-insights"   = "true"
  }
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  max_retries       = 0
  timeout           = 2880
  tags = {
    Name        = "B3 Visual ETL"
    Environment = var.environment
  }
}

# IAM Role for Lambda and Glue
resource "aws_iam_role" "lambda_glue_role" {
  name = "LabRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "glue.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.lambda_glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "lambda_s3_glue_policy" {
  name = "LambdaS3GluePolicy"
  role = aws_iam_role.lambda_glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:*"],
        Resource = [
          "arn:aws:s3:::fiap-2025-tech02-b3-glue-119268833495",
          "arn:aws:s3:::fiap-2025-tech02-b3-glue-119268833495/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJob"
        ],
        Resource = [
          "arn:aws:glue:us-east-1:119268833495:job/b3-visual-etl"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:BatchCreatePartition"
        ],
        Resource = [
          "arn:aws:glue:us-east-1:119268833495:catalog",
          "arn:aws:glue:us-east-1:119268833495:database/b3_database",
          "arn:aws:glue:us-east-1:119268833495:table/b3_database/b3_refined"
        ]
      }
    ]
  })
}

# Nome do job visual
locals {
  visual_job_name = "b3-visual-etl"
}

# Obter informações da conta atual
data "aws_caller_identity" "current" {}

# Outputs importantes para segurança
output "bucket_name" {
  description = "Nome do bucket S3 criado"
  value       = aws_s3_bucket.b3_glue.id
}

output "bucket_arn" {
  description = "ARN do bucket S3"
  value       = aws_s3_bucket.b3_glue.arn
}

output "lambda_function_name" {
  description = "Nome da função Lambda"
  value       = aws_lambda_function.glue_trigger.function_name
}

output "glue_job_visual_name" {
  description = "Nome do job visual do Glue"
  value       = local.visual_job_name
}

output "account_id" {
  description = "ID da conta AWS (para verificação de acesso)"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

output "glue_visual_job_parameters" {
  description = "Parâmetros para configurar o Glue Visual Job"
  value = {
    job_name        = local.visual_job_name
    source_bucket   = aws_s3_bucket.b3_glue.bucket
    target_bucket   = aws_s3_bucket.b3_glue.bucket
    temp_dir        = "s3://${aws_s3_bucket.b3_glue.bucket}/temp/"
    iam_role        = "LabRole"
    glue_version    = "4.0"
    worker_type     = "G.1X"
    number_workers  = 2
  }
}