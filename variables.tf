variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "cloud-soar"
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "approval_timeout" {
  type    = number
  default = 45
}

variable "key_approval_timeout" {
  type    = number
  default = 120
}

variable "lambda_reserved_concurrency" {
  type        = number
  default     = 5
  description = "Reserved concurrency per Lambda. New AWS accounts with low limits may need -1."
}

variable "remediation_bucket_arns" {
  type        = list(string)
  default     = ["arn:aws:s3:::cloud-soar-*"]
  description = "Buckets the S3 remediation Lambda may change. Extend this list for your own buckets."
}
