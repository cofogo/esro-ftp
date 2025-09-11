variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store generated manifests"
  type        = string
  default     = "sympany-clothing-data"
}

variable "s3_bucket_path" {
  description = "Path prefix within the S3 bucket for storing manifests"
  type        = string
  default     = "manifests"
  sensitive   = true
}

# Database connection variables for Parameter Store (referencing existing Sympany parameters)
variable "db_user_parameter" {
  description = "SSM Parameter Store path for database username"
  type        = string
  default     = "/sympany/POSTGRES_USER"
}

variable "db_password_parameter" {
  description = "SSM Parameter Store path for database password"
  type        = string
  default     = "/sympany/POSTGRES_PASSWORD"
}

variable "db_name_parameter" {
  description = "SSM Parameter Store path for database name"
  type        = string
  default     = "/sympany/POSTGRES_DB"
}

variable "db_host_parameter" {
  description = "SSM Parameter Store path for database host"
  type        = string
  default     = "/sympany/POSTGRES_URL"
}

variable "aws_region_parameter" {
  description = "SSM Parameter Store path for AWS region"
  type        = string
  default     = "/sympany/AWS_REGION"
}

variable "private_subnets" {
  description = "Private subnet IDs where the Lambda will run"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Security group ID to attach to the Lambda ENIs"
  type        = string
}


