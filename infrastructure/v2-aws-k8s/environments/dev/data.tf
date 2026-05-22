# ==========================================
# DATA SOURCES: Fetching the V1 Foundation
# ==========================================

data "aws_caller_identity" "current" {}

# 1. Fetch the existing V1 VPC
data "aws_vpc" "rr_v1_vpc" {
  tags = {
    Environment = var.environment
    Name        = "rr-${var.environment}-vpc"
  }
}

# 2. Fetch the existing RDS Security Group
data "aws_security_group" "rr_v1_rds_sg" {
  tags = {
    Environment = var.environment
    Name        = "rr-${var.environment}-rds-sg"
  }
}


# Fetch the Existing Internet gateway
data "aws_internet_gateway" "rr_v1_igw" {

  # These are the tags attached to the IGW from V1, retrieved from the IGW itself
  tags = {
    Project        = "ritual-roast-ECS"
    Project_owner  = "Elvy ManunEbo"
    Terraform      = "true"
    Environment    = var.environment
    Region         = var.aws_region
    aws_account_id = data.aws_caller_identity.current.account_id
    s3_bucket      = "rr-capstone-5b160b287a99a6d9"
  }
}

# Fetch aws_subnet.public_subnets[1].id
data "aws_subnet" "rr_v1_public_subnet_1" {
  tags = {
    Project        = "ritual-roast-ECS"
    Project_owner  = "Elvy ManunEbo"
    Terraform      = "true"
    Environment    = var.environment
    Region         = var.aws_region
    aws_account_id = data.aws_caller_identity.current.account_id
    s3_bucket      = "rr-capstone-5b160b287a99a6d9"
    Name = "PublicSubnet-01-2a"
  }
}