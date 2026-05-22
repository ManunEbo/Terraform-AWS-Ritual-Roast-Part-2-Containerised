variable "vpc_id" {
  description = "The ID of the VPC where SGs will be created"
  type        = string
}

variable "vpc_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "aws_region" {
  description = "The AWS region for fetching dynamic prefix lists"
  type        = string
}