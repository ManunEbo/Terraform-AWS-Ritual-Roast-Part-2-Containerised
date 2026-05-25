variable "environment" {
  type = string
}

variable "aws_region" {
    type = string  
}

variable "aws_account_id" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "s3_bucket" {
    type = string
}