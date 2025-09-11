output "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch EventBridge rule for S3 upload trigger"
  value       = aws_cloudwatch_event_rule.s3_upload_trigger.name
}
