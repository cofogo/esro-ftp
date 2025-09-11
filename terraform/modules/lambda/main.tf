# ECR Repository for the dataset manifest generator
resource "aws_ecr_repository" "s3_upload_trigger" {
  name                 = "s3-upload-trigger"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "s3-upload-trigger"
    Environment = "production"
  }
}

resource "aws_ecr_lifecycle_policy" "s3_upload_trigger_policy" {
  repository = aws_ecr_repository.s3_upload_trigger.name
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

resource "aws_lambda_function" "s3_upload_trigger" {
  function_name = "s3-upload-trigger"
  role          = var.lambda_execution_role_arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.s3_upload_trigger.repository_url}:latest"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      S3_SECRET_NAME = var.s3_secret_name
      S3_BUCKET      = var.s3_bucket_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = {
    Name        = "s3-upload-trigger"
    Environment = "production"
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/s3-upload-trigger"
  retention_in_days = 14

  tags = {
    Name        = "s3-upload-trigger-logs"
    Environment = "production"
  }
}
