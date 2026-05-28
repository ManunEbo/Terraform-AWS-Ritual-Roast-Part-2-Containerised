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

variable "k8s_subnet_list" {
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
