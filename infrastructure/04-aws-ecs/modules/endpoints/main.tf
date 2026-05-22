#--------------------------------------------------------------
#  Interface Endpoints (Secrets Manager, ECR, ECS)
#--------------------------------------------------------------

# Secrets Manager: For lambda rotation and App secret retrieval
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [var.endpoints_sg_id]
  subnet_ids          = var.app_subnet_ids
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-secrets-endpoint"
  })
}

# ECR API: for ECS to describe images
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [var.endpoints_sg_id]
  subnet_ids          = var.app_subnet_ids
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-ecr-api-endpoint"
  })
}

# ECR docker: For actually pulling the image layers
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [var.endpoints_sg_id]
  subnet_ids          = var.app_subnet_ids
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-ecr-dkr-endpoint"
  })
}

# CloudWatch Logs VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  
  # Deploying into the App subnets where the Fargate tasks live
  subnet_ids          = var.app_subnet_ids
  
  # Attaching to the same endpoints security group you already built
  security_group_ids  = [var.endpoints_sg_id]
  
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-logs-endpoint"
  })
}

# This Gateway is what makes your private subnets "NAT-less" for ECR pulls.
# It injects a private route into your PRIVATE route table only.
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id            = var.vpc_id
#   service_name      = "com.amazonaws.${var.aws_region}.s3"
#   vpc_endpoint_type = "Gateway"

#   # Assign the list variable directly without brackets
#   route_table_ids   = var.private_route_table_id

#   tags = merge(var.common_tags, {
#     Name = "rr-${var.environment}-s3-gateway"
#   })
# }