variable "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store generated manifests"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
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
