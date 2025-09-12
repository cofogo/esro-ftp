terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"

  cloud {
    organization = "Code-for-Good"
    workspaces {
      name = "esro-ftp"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "iam" {
  source = "./modules/iam"

  aws_region     = var.aws_region
  s3_bucket_name = var.s3_bucket_name
}

# Lambda Module - Functions and ECR
module "lambda" {
  source = "./modules/lambda"

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  s3_secret_name            = aws_secretsmanager_secret.s3_config.name
  s3_bucket_name            = var.s3_bucket_name

  subnet_ids         = var.private_subnets
  security_group_ids = [var.lambda_security_group_id]

  depends_on = [module.iam, aws_secretsmanager_secret.s3_config]
}

module "step_function" {
  source              = "./modules/step_function"
  lambda_function_arn = module.lambda.lambda_function_arn
  aws_region          = var.aws_region
}

module "cloudwatch" {
  source            = "./modules/cloudwatch"
  aws_region        = var.aws_region
  s3_bucket_name    = var.s3_bucket_name
  step_function_arn = module.step_function.state_machine_arn
}

# AWS Secrets Manager secret for S3 configuration
resource "aws_secretsmanager_secret" "s3_config" {
  name        = "s3-upload-trigger/s3"
  description = "S3 configuration for s3-upload-trigger"

  tags = {
    Name        = "s3-upload-trigger-s3-secret"
    Environment = "production"
  }
}

resource "aws_secretsmanager_secret_version" "s3_config" {
  secret_id = aws_secretsmanager_secret.s3_config.id
  secret_string = jsonencode({
    bucket_name = var.s3_bucket_name
  })
}


