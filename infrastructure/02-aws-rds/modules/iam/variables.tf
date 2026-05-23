variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "aws_account_id" {
  type = string
}