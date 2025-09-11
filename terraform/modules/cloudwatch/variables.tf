variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to trigger on upload"
  type        = string
}

variable "step_function_arn" {
  description = "ARN of the Step Function state machine to trigger"
  type        = string
}
