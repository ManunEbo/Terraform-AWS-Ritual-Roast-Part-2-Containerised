# ==========================================
# 1. Common tags from V1
# ==========================================
locals {
  common_tags_vpc = {
    Project        = "ritual-roast-ECS"
    Project_owner  = "Elvy ManunEbo"
    Terraform      = "true"
    Environment    = "dev"
    Region         = "eu-west-2"
  }
}

# ==========================================
# DATA SOURCES: Fetching the V1 Foundation
# ==========================================

data "aws_caller_identity" "current" {}

# 1. Fetch the existing V1 VPC
data "aws_vpc" "rr_v1_vpc" {
  tags = merge(local.common_tags_vpc, {
    Name        = "rr-${var.environment}-RR-vpc"
  })
}


# Fetching private route table id
data "aws_route_table" "rr_vpc_private_rt" {
  tags =  merge(local.common_tags_vpc, {
    Name = "rr-${var.environment}-${var.vpc_name}-private-rt"
  })
}





