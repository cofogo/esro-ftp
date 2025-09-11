# ECR Repository for the dataset manifest generator
resource "aws_ecr_repository" "dataset_manifest_generator" {
  name                 = "dataset-manifest-generator"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "dataset-manifest-generator"
    Environment = "production"
  }
}

resource "aws_ecr_lifecycle_policy" "dataset_manifest_generator_policy" {
  repository = aws_ecr_repository.dataset_manifest_generator.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lambda function for dataset manifest generation
resource "aws_lambda_function" "dataset_manifest_generator" {
  function_name = "dataset-manifest-generator"
  role          = var.lambda_execution_role_arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.dataset_manifest_generator.repository_url}:latest"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      DB_USER_PARAMETER     = var.db_user_parameter
      DB_PASSWORD_PARAMETER = var.db_password_parameter
      DB_NAME_PARAMETER     = var.db_name_parameter
      DB_HOST_PARAMETER     = var.db_host_parameter
      S3_SECRET_NAME        = var.s3_secret_name
      S3_BUCKET             = var.s3_bucket_name
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = {
    Name        = "dataset-manifest-generator"
    Environment = "production"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/dataset-manifest-generator"
  retention_in_days = 14

  tags = {
    Name        = "dataset-manifest-generator-logs"
    Environment = "production"
  }
}
