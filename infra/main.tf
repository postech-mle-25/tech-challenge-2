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
  filename         = "glue_trigger.zip"
  function_name    = "b3-glue-trigger"
  role            = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      JOB_NAME = local.visual_job_name
    }
  }

  tags = {
    Name        = "B3 Glue Trigger"
    Environment = var.environment
  }
}

# Permissão para S3 invocar Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.glue_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.b3_glue.arn
}

# Job do Glue Visual será criado manualmente no AWS Glue Studio
# para habilitar a interface visual com drag & drop
# 
# INSTRUÇÕES PARA CRIAÇÃO MANUAL:
# 1. Acesse AWS Glue Studio
# 2. Clique em "Create job" 
# 3. Selecione "Visual with a blank canvas"
# 4. Configure:
#    - Job name: "b3-visual-etl"
#    - IAM Role: "LabRole" 
#    - Glue version: "4.0"
#    - Worker type: "G.1X"
#    - Number of workers: 2
#    - Job parameters recomendados:
#      --source-bucket: [USE O VALOR DO OUTPUT bucket_name]
#      --target-bucket: [USE O VALOR DO OUTPUT bucket_name]
#      --TempDir: s3://[USE O VALOR DO OUTPUT bucket_name]/temp/

# Nome do job visual que será criado manualmente
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
  description = "Nome do job visual do Glue (criado manualmente)"
  value       = local.visual_job_name
}

output "account_id" {
  description = "ID da conta AWS (para verificação de acesso)"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

output "glue_visual_job_parameters" {
  description = "Parâmetros para configurar o Glue Visual Job manualmente"
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
