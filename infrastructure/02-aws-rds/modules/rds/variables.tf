variable "environment" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "common_tags" {
  type = map(string)
}

variable "database_sg_id" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
}

variable "rotation_lambda_arn" {
  type = string
}