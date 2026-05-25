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
  tags = local.common_tags_vpc
  
  filter {
    name = "tag:Name"
    values = ["rr-${var.environment}-*"]
  }
}


# Fetching private route table id
data "aws_route_table" "rr_vpc_private_rt" {
  tags =  merge(local.common_tags_vpc, {
    Name = "rr-${var.environment}-${var.vpc_name}-private-rt"
  })
}

# ==========================================
# Fetching the database subnets
# ==========================================

data "aws_subnets" "rr_db_subnets" {
  # 1. Filter by the common tags to ensure we're in the right VPC/Environment
  tags = local.common_tags_vpc

  # 2. Use a dynamic filter to catfhc subnets via a wildcard
  filter {
    name = "tag:Name"
    values = ["DataSubnet-*"]
  }
}