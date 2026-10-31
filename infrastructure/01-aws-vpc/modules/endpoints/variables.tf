variable "vpc_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "app_subnet_ids" {
  description = "Subnets where the endpoint network interfaces will live"
  type        = list(string)
}

variable "endpoints_sg_id" {
  description = "The ID of the VPC Endpoints Security Group"
  type        = string
}

variable "private_route_table_ids" {
  description = "Route tables the s3 gateway endpoint is attached to"
  type        = list(string)
}