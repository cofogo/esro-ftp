# IAM Role for Step Function
resource "aws_iam_role" "step_function_role" {
  name = "dataset-manifest-generator-step-function-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "dataset-manifest-generator-step-function-role"
    Environment = "production"
  }
}

# Policy for Step Function to invoke Lambda
resource "aws_iam_policy" "step_function_lambda_policy" {
  name        = "dataset-manifest-generator-step-function-policy"
  description = "Policy for Step Function to invoke Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = var.lambda_function_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_function_lambda_policy" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.step_function_lambda_policy.arn
}

# Step Function State Machine
resource "aws_sfn_state_machine" "dataset_manifest_generator" {
  name     = "dataset-manifest-generator"
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    Comment = "Generate dataset manifests monthly"
    StartAt = "GenerateManifests"
    States = {
      GenerateManifests = {
        Type     = "Task"
        Resource = var.lambda_function_arn
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 2
            MaxAttempts     = 6
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleError"
          }
        ]
        End = true
      }
      HandleError = {
        Type  = "Fail"
        Cause = "Lambda function failed to generate manifests"
      }
    }
  })

  tags = {
    Name        = "dataset-manifest-generator"
    Environment = "production"
  }
}
