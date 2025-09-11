variable "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  type        = string
}

variable "db_user_parameter" {
  description = "SSM Parameter Store path for database username"
  type        = string
}

variable "db_password_parameter" {
  description = "SSM Parameter Store path for database password"
  type        = string
}

variable "db_name_parameter" {
  description = "SSM Parameter Store path for database name"
  type        = string
}

variable "db_host_parameter" {
  description = "SSM Parameter Store path for database host"
  type        = string
}

variable "s3_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing S3 configuration"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store generated manifests"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the Lambda to run in"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the Lambda"
  type        = list(string)
}
