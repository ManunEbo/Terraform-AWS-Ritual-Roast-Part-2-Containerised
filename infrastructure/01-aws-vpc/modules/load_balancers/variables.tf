variable "vpc_id" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "public_subnet_ids" {
  description = "List of Public Subnet IDs for the Public ALB"
  type        = list(string)
}


variable "public_alb_sg_id" {
  description = "The Public ALB Security Group ID"
  type        = string
}


variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}
