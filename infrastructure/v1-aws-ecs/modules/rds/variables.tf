variable "environment" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

# FIXED: Changed from list to map to work with Terraform merge()
variable "common_tags" {
  type = map(string)
}

variable "database_sg_id" {
  type = string
}

# FIXED: Removed var.rr_db_skeleton because that resource is created inside this module!

variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
}

variable "rotation_lambda_arn" {
  type = string
}