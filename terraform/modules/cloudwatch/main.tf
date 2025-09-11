resource "aws_cloudwatch_event_rule" "s3_upload_trigger" {
  name          = "s3-upload-trigger"
  description   = "Trigger on file upload to esro-ftp bucket"
  event_pattern = <<EOF
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "resources": [
    "arn:aws:s3:::${var.s3_bucket_name}"
  ]
}
EOF

  tags = {
    Name        = "s3-upload-trigger"
    Environment = "production"
  }
}

resource "aws_cloudwatch_event_target" "step_function_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload_trigger.name
  target_id = "EsroFtpStepFunctionTarget"
  arn       = var.step_function_arn
}
