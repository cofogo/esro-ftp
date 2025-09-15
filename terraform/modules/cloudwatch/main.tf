resource "aws_cloudwatch_event_rule" "s3_upload_trigger" {
  name          = "s3-upload-trigger"
  description   = "Trigger on file upload to esro-ftp bucket"
  event_pattern = <<EOF
{
  "source": ["aws.s3"],
  "detail": {
    "bucket": {
      "name": ["${var.s3_bucket_name}"]
    }
  },
  "detail-type": [
    "Object Created"
  ]
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

# CloudWatch Log Group for EventBridge debugging
resource "aws_cloudwatch_log_group" "eventbridge_logs" {
  name              = "/aws/events/s3-upload-trigger"
  retention_in_days = 7

  tags = {
    Name        = "s3-upload-trigger-eventbridge-logs"
    Environment = "production"
  }
}

# CloudWatch Log Stream for EventBridge rule
resource "aws_cloudwatch_log_stream" "eventbridge_log_stream" {
  name           = "eventbridge-rule-logs"
  log_group_name = aws_cloudwatch_log_group.eventbridge_logs.name
}

resource "aws_cloudwatch_event_target" "step_function_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload_trigger.name
  target_id = "EsroFtpStepFunctionTarget"
  arn       = var.step_function_arn
  role_arn  = aws_iam_role.eventbridge_role.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      region = "$.detail.awsRegion"
    }
    input_template = <<EOF
{
  "bucket": "<bucket>",
  "key": "<key>",
  "region": "<region>",
  "s3_path": "s3://<bucket>/<key>"
}
EOF
  }
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
