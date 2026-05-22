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

variable "rr_v1_public_subnet_1_id" {
    description = "V1 Public Subnet ID for placing the NAT Gateway"
    type        = string
}

variable "rr_v1_igw" {
    description = "The V1 internet gateway ID"
    type        = string
}

variable "k8s_subnet_list" {
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}