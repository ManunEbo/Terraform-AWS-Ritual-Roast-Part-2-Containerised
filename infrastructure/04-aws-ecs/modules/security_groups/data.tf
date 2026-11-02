# 1. Fetching the AWS Managed S3 Prefix List (For VPC Endpoints). Note this is region specific
# (Defining it here makes it available for all SGs in this module)

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

# 2. Fetching Layer 1: Public ALB Security Group Shell
data "aws_security_group" "public_alb_sg" {
  vpc_id = var.vpc_id
  name   = "rr-${var.environment}-alb-sg"
}


# 3. Fetching Layer 2: Database Security Group Shell
data "aws_security_group" "database_sg" {
  vpc_id = var.vpc_id
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-database-sg"]
  }
}

# 4. Fetching Layer 2: Lambda Security Group Shell
data "aws_security_group" "lambda_sg" {
  vpc_id = var.vpc_id
  name   = "rr-${var.environment}-lambda-sg"
}

# Fetch the Endpoints Security Group from Layer 1
data "aws_security_group" "rr_endpoints_sg" {
  vpc_id = var.vpc_id
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-vpc-endpoints-sg"]
  }
}