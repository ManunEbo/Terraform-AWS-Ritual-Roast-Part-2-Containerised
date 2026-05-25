 #==========================================
# 1. Common tags from V1
# =========================================
locals {
  common_tags_vpc = {
    Project        = "ritual-roast-ECS"
    Project_owner  = "Elvy ManunEbo"
    Terraform      = "true"
    Environment    = "dev"
    Region         = "eu-west-2"
  }
}


# ===============================================
# DATA SOURCES: Fetching the Layer-1 Foundation
# ===============================================
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# 1. Fetch the existing V1 VPC
data "aws_vpc" "rr_vpc" {
  tags = local.common_tags_vpc  
  filter {
    name = "tag:Name"
    values = ["rr-${var.environment}-*"]
  }
}


# Retrieve Frontend subnets
data "aws_subnets" "web_subnets" {
    tags = local.common_tags_vpc
    filter {
      name = "tag:Name"
      values = ["WebSubnet-*"]
    }
}

# Retrieve Backend subnets
data "aws_subnets" "AppSubnets" {
    tags = local.common_tags_vpc

    filter {
      name = "tag:Name"
      values = ["AppSubnet-*"]
    }
}

# Retrieve Frontend ALB Target Group
data "aws_alb_target_group" "frontend_tgt" {
    name = "rr-${var.environment}-frontend-tg"
}

data "aws_security_group" "public_alb_sg" {
  name = "rr-${var.environment}-alb-sg"
}


