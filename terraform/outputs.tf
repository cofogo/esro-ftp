output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.lambda.ecr_repository_url
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.lambda.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda.lambda_function_name
}

output "step_function_arn" {
  description = "ARN of the Step Function state machine"
  value       = module.step_function.state_machine_arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for monthly execution"
  value       = aws_cloudwatch_event_rule.monthly_trigger.name
}

output "s3_secret_arn" {
  description = "ARN of the S3 configuration secret"
  value       = aws_secretsmanager_secret.s3_config.arn
  sensitive   = true
}

output "s3_secret_name" {
  description = "Name of the S3 configuration secret"
  value       = aws_secretsmanager_secret.s3_config.name
}
