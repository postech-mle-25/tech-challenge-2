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
