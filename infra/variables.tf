variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "Academy"
}

variable "force_destroy" {
  description = "Force destroy bucket even if not empty"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "account_id" {
  description = "ID da conta AWS para ARNs e nomes de recursos"
  type        = string
  default     = "119268833495"  # Altere apenas aqui para mudar em todo o projeto
}

variable "bucket_name_prefix" {
  description = "Prefixo do nome do bucket S3 para armazenar dados da B3"
  type        = string
  default     = "fiap-2025-tech02-b3-glue"
}