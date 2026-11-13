variable "environment" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "public_subnet_id" {
  type = string
}

variable "vpc_id" {
  type = string
}