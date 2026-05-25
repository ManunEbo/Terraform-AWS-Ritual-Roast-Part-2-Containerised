# ==========================================
# 1. Common tags from 01-aws-vpc
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

# ================================================
# DATA SOURCES: Fetching the 01-aws-vpc resources
# ================================================

data "aws_caller_identity" "current" {}

# 1. Fetch the existing 01-aws-vpc VPC
data "aws_vpc" "rr_vpc" {
  tags = merge(local.common_tags_vpc, {
    Name        = "rr-${var.environment}-RR-vpc"
  })
}

# 2. Fetch the existing RDS Security Group
data "aws_security_group" "rr_rds_sg" {
  tags = merge(local.common_tags_vpc, {
    Name        = "rr-${var.environment}-rds-sg"
  })
}


# Fetch the Existing Internet gateway
data "aws_internet_gateway" "rr_igw" {

  # These are the tags attached to the IGW from 01-aws-vpc, retrieved from the IGW itself
  tags = merge(local.common_tags_vpc, {
    Name = "${var.environment}-igw"
  })
}

# Fetch aws_subnet.public_subnets[1].id
data "aws_subnet" "rr_public_subnet_1" {
  tags = merge(local.common_tags_vpc, {
    Name = "PublicSubnet-01-2a"
  })
}

# Fetching the k8s subnets
data "aws_subnets" "rr_k8s_subnets" {
  tags = local.common_tags_vpc
  
  filter {
    name = "tag:Name"
    values = ["K8sSubnet-*"]
  }
}

# retrieve the private route table for K8s
data "aws_route_table" "rr_k8s_private_rt" {
  tags = merge(local.common_tags_vpc, {
    Name = "rr-${var.environment}-${data.aws_vpc.rr_vpc.vpc_name}-k8s-private-rt"
  })
}

# ======================================================
# DATA SOURCES: Fetching the 01-aws-vpc security groups
# ======================================================

# 3. Fetch 01-aws-vpc ALB Security Group
data "aws_security_group" "rr_public_alb_sg" {

  tags = merge(local.common_tags_vpc, {
     Name        = "rr-${var.environment}-alb-sg"
  })
}

# 4. Fetch Frontend (Web) Security Group
data "aws_security_group" "rr_web_sg" {

  tags = merge(local.common_tags_vpc, {
    Name        = "rr-${var.environment}-frontend-sg" 
  })
}

# 5. Fetch Backend (App) Security Group
data "aws_security_group" "rr_app_sg" {
  
  tags = merge(local.common_tags_vpc, {
    Name        = "rr-${var.environment}-backend-sg" 
  })
}