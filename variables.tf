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
