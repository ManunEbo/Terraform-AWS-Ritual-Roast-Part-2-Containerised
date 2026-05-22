# ==========================================
# 1. Common tags from V1
# ==========================================
locals {
  common_tags_v1 = {
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
  tags = merge(local.common_tags_v1, {
    Name        = "rr-${var.environment}-RR-vpc"
  })
}

# 2. Fetch the existing RDS Security Group
data "aws_security_group" "rr_v1_rds_sg" {
  tags = merge(local.common_tags_v1, {
    Name        = "rr-${var.environment}-rds-sg"
  })
}


# Fetch the Existing Internet gateway
data "aws_internet_gateway" "rr_v1_igw" {

  # These are the tags attached to the IGW from V1, retrieved from the IGW itself
  tags = merge(local.common_tags_v1, {
    Name = "${var.environment}-igw"
  })
}

# Fetch aws_subnet.public_subnets[1].id
data "aws_subnet" "rr_v1_public_subnet_1" {
  tags = merge(local.common_tags_v1, {
    Name = "PublicSubnet-01-2a"
  })
}

# ==============================================
# DATA SOURCES: Fetching the V1 security groups
# ==============================================

# 3. Fetch V1 ALB Security Group
data "aws_security_group" "rr_v1_alb_sg" {

  tags = merge(local.common_tags_v1, {
     Name        = "rr-${var.environment}-alb-sg"
  })
}

# 4. Fetch V1 Frontend (Web) Security Group
data "aws_security_group" "rr_v1_web_sg" {

  tags = merge(local.common_tags_v1, {
    Name        = "rr-${var.environment}-frontend-sg" 
  })
}

# 5. Fetch V1 Backend (App) Security Group
data "aws_security_group" "rr_v1_app_sg" {
  
  tags = merge(local.common_tags_v1, {
    Name        = "rr-${var.environment}-backend-sg" 
  })
}