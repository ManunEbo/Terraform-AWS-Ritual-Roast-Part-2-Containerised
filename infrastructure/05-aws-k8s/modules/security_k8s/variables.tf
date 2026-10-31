variable "environment" {
  description = "The deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the Shared V1 VPC"
  type        = string
}

variable "rds_sg_id" {
  description = "The Security Group ID of the V1 RDS instance"
  type        = string
}

variable "common_tags" {
  description = "Common tags from the shared locals"
  type        = map(string)
}

variable "alb_sg_id" {
  description = "Security Group ID of the V1 ALB"
  type        = string
}

# variable "web_sg_id" {
#   description = "Security Group ID of the V1 Frontend Web tasks"
#   type = string
# }

# variable "app_sg_id" {
#   description = "Security Group ID of the V1 Backend App tasks"
#   type = string
# }

variable "github_pat" {
  type      = string
  sensitive = true
}

variable "grafana_token" {
  type      = string
  sensitive = true
}

variable "grafana_remote_write_url" {
  type      = string
  sensitive = true
}

variable "grafana_instance_id" {
  type      = string
  sensitive = true
}

variable "endpoints_sg_id" {
  description = "Layer 1 VPC Endpoints Security Group ID"
  type        = string
}