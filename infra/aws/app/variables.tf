variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "app_name" {
  type    = string
  default = "cloudpose"
}

variable "image_tag" {
  type        = string
  default     = "0.3.0"
  description = "Tag of the image pushed to ECR"
}

variable "container_port" {
  type    = number
  default = 60007
}

# Fargate sizes: 1024 = 1 vCPU, 2048 = 2 GB. TensorFlow + model use ~0.4-0.5 GB.
variable "task_cpu" {
  type    = number
  default = 1024
}

variable "task_memory" {
  type    = number
  default = 2048
}

variable "min_tasks" {
  type    = number
  default = 1
}

variable "max_tasks" {
  type    = number
  default = 3
}

variable "cpu_target_percent" {
  type        = number
  default     = 60
  description = "Target-tracking autoscaling keeps average task CPU near this"
}

variable "alert_email" {
  type        = string
  default     = ""
  description = "Email for alarm notifications (leave empty to skip). Confirm the email AWS sends."
}

variable "github_repo" {
  type        = string
  default     = ""
  description = "GitHub repo allowed to deploy, as owner/repo (e.g. anbu/cloudpose-aws). Empty = no CD role."
}

variable "cd_auth" {
  type        = string
  default     = "oidc"
  description = "How GitHub Actions logs in to AWS: oidc (best practice) or iam_user (fallback when an SCP blocks OIDC providers)"

  validation {
    condition     = contains(["oidc", "iam_user"], var.cd_auth)
    error_message = "cd_auth must be \"oidc\" or \"iam_user\"."
  }
}
