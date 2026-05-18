variable "aws_region" { type = string }
variable "vpc_name" { type = string }
variable "vpc_cidr" { type = string }
variable "environment" { type = string }

variable "public_subnet_list" {
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}

variable "web_subnet_list" {
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}

variable "app_subnet_list" {
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}

variable "database_subnet_list" {
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}

variable "common_tags" {
  description = "A map of common tags to apply to all resources"
  type        = map(string)
}