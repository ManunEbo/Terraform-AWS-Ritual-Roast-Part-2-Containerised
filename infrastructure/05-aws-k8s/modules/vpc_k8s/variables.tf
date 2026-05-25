variable "environment" {
  description = "The deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the Shared V1 VPC"
  type        = string
}

variable "vpc_name" {
  type = string
}

variable "common_tags" {
  description = "Common tags from the shared locals"
  type        = map(string)
}

variable "rr_public_subnet_1_id" {
    description = "V1 Public Subnet ID for placing the NAT Gateway"
    type        = string
}

variable "rr_igw" {
    description = "The V1 internet gateway ID"
    type        = string
}

variable "rr_k8s_private_rt_id" {
  type = string
}

variable "rr_k8s_subnets_ids" {
  type = list(string)
}