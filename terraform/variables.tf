variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store generated manifests"
  type        = string
  default     = "esro-ftp"
}

variable "private_subnets" {
  description = "Private subnet IDs where the Lambda will run"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Security group ID to attach to the Lambda ENIs"
  type        = string
}
