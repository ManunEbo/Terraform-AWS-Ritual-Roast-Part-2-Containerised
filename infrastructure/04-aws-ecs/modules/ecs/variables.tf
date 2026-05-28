variable "vpc_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "ecs_execution_role_arn" {
  description = "The ARN of the IAM role used by the Fargate agent"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "The ARN of the IAM  role used by the application code"
  type        = string
}

# --- CORRECTED: Description now accurately reflects the private architecture ---
variable "frontend_subnets" {
  description = "List of private subnets for the frontend service"
  type        = list(string)
}

variable "backend_subnets" {
  description = "List of app/private subnets for the backend service"
  type        = list(string)
}

variable "frontend_sg_id" {
  description = "Security group ID for the frontend containers"
  type        = string
}

variable "backend_sg_id" {
  description = "Security group ID for the backend containers"
  type        = string
}

variable "frontend_tg_arn" {
  description = "The ARN of the frontend target group"
  type        = string
}

variable "backend_tg_arn" {
  description = "The ARN of the backend target group"
  type        = string
}

# --- NEW VARIABLES FOR CONTAINER ENVIRONMENTS ---

variable "internal_alb_dns_name" {
  description = "The DNS name of the internal ALB for frontend routing"
  type        = string
}
