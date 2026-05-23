variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "lambda_role_arn" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "lambda_sg_id" {
  type = string
}