#==========================================
# 1. Common tags from V1
# =========================================
locals {
  common_tags_vpc = {
    Project       = "ritual-roast-ECS"
    Project_owner = "Elvy ManunEbo"
    Terraform     = "true"
    Environment   = "dev"
    Region        = "eu-west-2"
  }
}


# ===============================================
# DATA SOURCES: Fetching the Layer-1 Foundation
# ===============================================
# data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# 1. Fetch the existing Layer 1 VPC
data "aws_vpc" "rr_vpc" {
  tags = local.common_tags_vpc
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-*"]
  }
}

# Fetching Public Networking for the ALB Module ---
data "aws_subnets" "public_subnets" {
  filter {
    name   = "tag:Name"
    values = ["PublicSubnet-*"]
  }
}

# Retrieve Frontend subnets
data "aws_subnets" "web_subnets" {
  tags = local.common_tags_vpc
  filter {
    name   = "tag:Name"
    values = ["WebSubnet-*"]
  }
}

# Retrieve Backend subnets
data "aws_subnets" "AppSubnets" {
  tags = local.common_tags_vpc

  filter {
    name   = "tag:Name"
    values = ["AppSubnet-*"]
  }
}


data "aws_security_group" "public_alb_sg" {
  name = "rr-${var.environment}-alb-sg"
}


data "aws_secretsmanager_secret" "rr_db_secret" {
  name = "rr-${var.environment}-db-secret"
}



# data "aws_security_group" "public_alb_sg" {
#   # Grabbing the public shell SG from Layer 1
#   name = "rr-${var.environment}-public-alb-sg" 
# }

data "aws_lb" "gateway_alb" {
  name = "rr-${var.environment}-public-alb"
}

data "aws_lb_listener" "gateway_http_listener" {
  load_balancer_arn = data.aws_lb.gateway_alb.arn
  port              = 80
}

data "aws_route_tables" "private_rts" {
  vpc_id = data.aws_vpc.rr_vpc.id

  # Assuming your private route tables have a common tag like Tier = app or private
  # Adjust this filter if your Layer 1 named them differently!
  filter {
    name   = "tag:Tier"
    values = ["app"]
  }
}

data "aws_security_group" "rr_endpoints_sg" {
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-vpc-endpoints-sg"]
  }
}