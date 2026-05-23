variable "environment" {
  description = "The deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the Shared V1 VPC"
  type        = string
}

variable "common_tags" {
  description = "Common tags from the shared locals"
  type        = map(string)
}


variable "database_subnet_list" {
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}

variable "rr_vpc_private_rt_id" {
  description = "VPC private route table ID"
  type = string
}