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

output "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch EventBridge rule for S3 upload trigger"
  value       = module.cloudwatch.cloudwatch_event_rule_name
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

# # FTP Server outputs
# output "ftp_server_instance_id" {
#   description = "ID of the FTP server EC2 instance"
#   value       = module.ec2.instance_id
# }

# output "ftp_server_public_ip" {
#   description = "Public IP address of the FTP server"
#   value       = module.ec2.public_ip
# }

# output "ftp_endpoint" {
#   description = "FTP server endpoint"
#   value       = module.ec2.ftp_endpoint
# }

# output "ftp_ssh_command" {
#   description = "SSH command to connect to the FTP server"
#   value       = module.ec2.ssh_command
# }
