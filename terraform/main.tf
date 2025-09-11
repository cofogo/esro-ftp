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
      name = "dataset-manifest-generator"
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
  db_user_parameter         = var.db_user_parameter
  db_password_parameter     = var.db_password_parameter
  db_name_parameter         = var.db_name_parameter
  db_host_parameter         = var.db_host_parameter
  s3_secret_name            = aws_secretsmanager_secret.s3_config.name
  s3_bucket_name            = var.s3_bucket_name

  subnet_ids         = var.private_subnets
  security_group_ids = [var.lambda_security_group_id]

  depends_on = [module.iam, aws_secretsmanager_secret.s3_config]
}

module "step_function" {
  source = "./modules/step_function"

  lambda_function_arn = module.lambda.lambda_function_arn
  aws_region          = var.aws_region
}

resource "aws_cloudwatch_event_rule" "monthly_trigger" {
  name                = "dataset-manifest-generator-monthly"
  description         = "Trigger dataset manifest generation monthly"
  schedule_expression = "cron(0 2 1 * ? *)" # First day of every month at 2 AM UTC

  tags = {
    Name        = "dataset-manifest-generator-monthly"
    Environment = "production"
  }
}

resource "aws_cloudwatch_event_target" "step_function_target" {
  rule      = aws_cloudwatch_event_rule.monthly_trigger.name
  target_id = "DatasetManifestGeneratorTarget"
  arn       = module.step_function.state_machine_arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}

# IAM Role for EventBridge to invoke Step Function
resource "aws_iam_role" "eventbridge_role" {
  name = "dataset-manifest-generator-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "dataset-manifest-generator-eventbridge-role"
    Environment = "production"
  }
}

resource "aws_iam_policy" "eventbridge_step_function_policy" {
  name        = "dataset-manifest-generator-eventbridge-policy"
  description = "Policy for EventBridge to invoke Step Function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = module.step_function.state_machine_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_step_function_policy" {
  role       = aws_iam_role.eventbridge_role.name
  policy_arn = aws_iam_policy.eventbridge_step_function_policy.arn
}

# AWS Secrets Manager secret for S3 configuration
resource "aws_secretsmanager_secret" "s3_config" {
  name        = "dataset-manifest-generator/s3"
  description = "S3 configuration for dataset manifest generator"

  tags = {
    Name        = "dataset-manifest-generator-s3-secret"
    Environment = "production"
  }
}

resource "aws_secretsmanager_secret_version" "s3_config" {
  secret_id = aws_secretsmanager_secret.s3_config.id
  secret_string = jsonencode({
    bucket_name = var.s3_bucket_name
    bucket_path = var.s3_bucket_path
  })
}


