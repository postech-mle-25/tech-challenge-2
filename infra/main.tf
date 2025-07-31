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
  s3_bucket        = var.bucket_name
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
    script_location = "s3://fiap-2025-tech02-b3-glue-119268833495/scripts/glue_job.py"
    name            = "glueetl"
  }
  default_arguments = {
    "--source-bucket"         = "fiap-2025-tech02-b3-glue-119268833495"
    "--target-bucket"         = "fiap-2025-tech02-b3-glue-119268833495"
    "--TempDir"               = "s3://fiap-2025-tech02-b3-glue-119268833495/temp/"
    "--job-bookmark-option"   = "job-bookmark-disable"
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
          "glue:UpdateTable"
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