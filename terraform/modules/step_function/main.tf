resource "aws_iam_role" "step_function_role" {
  name = "s3-upload-trigger-step-function-role"
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
    Name        = "s3-upload-trigger-step-function-role"
    Environment = "production"
  }
}

resource "aws_iam_policy" "step_function_lambda_policy" {
  name        = "s3-upload-trigger-step-function-policy"
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

resource "aws_sfn_state_machine" "s3_upload_trigger" {
  name     = "s3-upload-trigger"
  role_arn = aws_iam_role.step_function_role.arn
  definition = jsonencode({
    Comment = "Process S3 upload trigger"
    StartAt = "ProcessS3Upload"
    States = {
      ProcessS3Upload = {
        Type     = "Task"
        Resource = var.lambda_function_arn
        Parameters = {
          "bucket.$"  = "$.bucket"
          "key.$"     = "$.key"
          "region.$"  = "$.region"
          "s3_path.$" = "$.s3_path"
        }
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
        Cause = "Lambda function failed to process S3 upload"
      }
    }
  })
  tags = {
    Name        = "s3-upload-trigger"
    Environment = "production"
  }
}
