variable "environment" {
  type = string
}

variable "gateway_listener_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "frontend_worker_asg_name" {
  description = "The name of the Frontend Worker Auto Scaling Group"
  type        = string
}