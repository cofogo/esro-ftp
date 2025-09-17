variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store generated manifests"
  type        = string
}

variable "management_bucket_name" {
  description = "Name of the S3 management data bucket"
  type        = string
  default     = "esro-management-data"
}
