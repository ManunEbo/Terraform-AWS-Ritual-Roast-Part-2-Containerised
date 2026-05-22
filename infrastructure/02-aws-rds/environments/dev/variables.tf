#--- Network Variables ---
variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "vpc_name" {
  type    = string
  default = "RR-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.16.0.0/16"
}

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

variable "environment" {
  type    = string
  default = "dev"
}

#--- Database credentials (sensitive) ---
variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

#--- S3 Config ---
variable "s3_bucket" {
  type = string
}

variable "app_source_bucket" {
  type    = string
  default = "rr-capstone-5b160b287a99a6d9"
}
