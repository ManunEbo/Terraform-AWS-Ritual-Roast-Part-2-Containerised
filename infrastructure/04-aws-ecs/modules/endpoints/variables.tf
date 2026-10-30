variable "vpc_id" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "environment" {
  type = string  
}

variable "endpoints_sg_id" {
  description = "The SG ID that allows 443 from App and lambda tiers"
  type        = string
}

variable "app_subnet_ids" {
  description = "Subnets where the endpoint network interfaces will live"
  type        = list(string)
}

variable "route_table_ids" {
  description = "A list of route table IDs to inject the S3 gateway route into"
  type        = list(string)
}


# --- Variables for tightening IAM policy for S3 endpoints ---

variable "ecs_execution_role_arn" {
  description = "IAM Role ARN used by Fargate to pull images"
  type        = string
}

variable "ecs_backend_task_role_arn" {
  description = "IAM Role ARN used by the backend application"
  type        = string
}

variable "ecs_frontend_task_role_arn" {
  description = "IAM Role ARN used by the frontend application"
  type        = string
}