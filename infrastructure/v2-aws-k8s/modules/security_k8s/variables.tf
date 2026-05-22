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