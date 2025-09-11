output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.dataset_manifest_generator.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.dataset_manifest_generator.function_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.dataset_manifest_generator.repository_url
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}
