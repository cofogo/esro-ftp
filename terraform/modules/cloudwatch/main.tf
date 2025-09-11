resource "aws_cloudwatch_event_rule" "s3_upload_trigger" {
  name          = "s3-upload-trigger"
  description   = "Trigger on file upload to esro-ftp bucket"
  event_pattern = <<EOF
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {
      "name": ["${var.s3_bucket_name}"]
    }
  }
}
EOF

  tags = {
    Name        = "s3-upload-trigger"
    Environment = "production"
  }
}

# S3 bucket notification configuration to send events to EventBridge
resource "aws_s3_bucket_notification" "s3_upload_notification" {
  bucket      = var.s3_bucket_name
  eventbridge = true
}

resource "aws_cloudwatch_event_target" "step_function_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload_trigger.name
  target_id = "EsroFtpStepFunctionTarget"
  arn       = var.step_function_arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}

# IAM Role for EventBridge to invoke Step Function
resource "aws_iam_role" "eventbridge_role" {
  name = "s3-upload-trigger-eventbridge-role"

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
    Name        = "s3-upload-trigger-eventbridge-role"
    Environment = "production"
  }
}

resource "aws_iam_policy" "eventbridge_step_function_policy" {
  name        = "s3-upload-trigger-eventbridge-policy"
  description = "Policy for EventBridge to invoke Step Function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = var.step_function_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_step_function_policy" {
  role       = aws_iam_role.eventbridge_role.name
  policy_arn = aws_iam_policy.eventbridge_step_function_policy.arn
}
