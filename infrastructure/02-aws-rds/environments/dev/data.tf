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


# locals {
#   db_subnets = {
#     "DataSubnet-01-2a" = "DataSubnet-01-2a"
#     "DataSubnet-02-2b" = "DataSubnet-02-2b"
#     "DataSubnet-03-2c" = "DataSubnet-03-2c"
#   }
# }

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

# ==========================================
# Fetching the database subnets
# ==========================================

# data "aws_subnets" "rr_db_subnets" {
#   for_each = local.db_subnets
#   tags = merge(local.common_tags_vpc, {
#     Name = "${each.value}"
#   })
# }

data "aws_subnet" "DataSubnet_2a" {
  tags = merge(local.common_tags_vpc, {
    Name = "DataSubnet-01-2a"
  })  
}

data "aws_subnet" "DataSubnet_2b" {
  tags = merge(local.common_tags_vpc, {
    Name = "DataSubnet-02-2b"
  })  
}

data "aws_subnet" "DataSubnet_2c" {
  tags = merge(local.common_tags_vpc, {
    Name = "DataSubnet-03-2c"
  })  
}