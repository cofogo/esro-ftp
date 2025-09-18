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

variable "management_bucket_name" {
  description = "Name of the S3 management data bucket"
  type        = string
  default     = "esro-management-data"
}

variable "certificate_bucket_name" {
  description = "Name of the S3 bucket containing certificates for mTLS"
  type        = string
  default     = "esro-certificates"
}

variable "private_subnets" {
  description = "Private subnet IDs where the Lambda will run"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Security group ID to attach to the Lambda ENIs"
  type        = string
}

# VPC and Network variables
variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID where the FTP server will be created"
  type        = string
}

# FTP Server variables
variable "ftp_instance_type" {
  description = "EC2 instance type for FTP server"
  type        = string
  default     = "t3.micro"
}

variable "ftp_username" {
  description = "FTP server username"
  type        = string
  default     = "ftpuser"
}

variable "ftp_password" {
  description = "FTP server password"
  type        = string
  sensitive   = true
}

variable "ftp_domain" {
  description = "Domain name for FTPS server (required for self-signed certificate)"
  type        = string
}

variable "ftp_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access FTP server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID for S3 access"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key for S3 access"
  type        = string
  sensitive   = true
}
