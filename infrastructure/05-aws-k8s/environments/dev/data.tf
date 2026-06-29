# ==========================================
# 1. Common tags from 01-aws-vpc
# ==========================================
locals {
  common_tags_vpc = {
    Project       = "ritual-roast-ECS"
    Project_owner = "Elvy ManunEbo"
    Terraform     = "true"
    Environment   = "dev"
    Region        = "eu-west-2"
  }
}

# ================================================
# DATA SOURCES: Fetching the 01-aws-vpc resources
# ================================================

# 1. Fetch the existing 01-aws-vpc VPC
data "aws_vpc" "rr_vpc" {
  tags = merge(local.common_tags_vpc, {
    Name = "rr-${var.environment}-RR-vpc"
  })
}

# 2. Fetch the existing RDS Security Group
data "aws_security_group" "rr_rds_sg" {
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-database-sg"] # <--- FIXED
  }
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
    name   = "tag:Name"
    values = ["K8sSubnet-*"]
  }
}

# ======================================================
# DATA SOURCES: Fetching the 01-aws-vpc security groups
# ======================================================

# 3. Fetch 01-aws-vpc ALB Security Group (Name standardized)
data "aws_security_group" "rr_alb_sg" {
  tags = merge(local.common_tags_vpc, {
    Name = "rr-${var.environment}-alb-sg"
  })
}

# 4. Fetch 01-aws-vpc Web Security Group
# data "aws_security_group" "rr_web_sg" {
#   tags = merge(local.common_tags_vpc, {
#     Name = "rr-${var.environment}-web-sg"
#   })
# }

# 5. Fetch 01-aws-vpc App Security Group
# data "aws_security_group" "rr_app_sg" {
#   tags = merge(local.common_tags_vpc, {
#     Name = "rr-${var.environment}-app-sg"
#   })
# }

data "aws_lb" "gateway_alb" {
  name = "rr-${var.environment}-public-alb"
}

data "aws_lb_listener" "gateway_http_listener" {
  load_balancer_arn = data.aws_lb.gateway_alb.arn
  port              = 80
}
# Fetch the Endpoints Security Group from Layer 1
data "aws_security_group" "rr_endpoints_sg" {
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-vpc-endpoints-sg"]
  }
}