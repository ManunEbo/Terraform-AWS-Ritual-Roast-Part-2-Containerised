#--- Network Variables ---
variable "vpc_name" {
  type    = string
  default = "RR-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.16.0.0/16"
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
