#--------------------------------------------------------------
#  Interface Endpoints (Secrets Manager, ECR, ECS, Logs)
#--------------------------------------------------------------


# The Secrets Manager interface endpoint has moved to Layer 1 to make it available to Layer 2,4 and 5
# (see infrastucture/01-aws-vpc/modules/endpoints/secrets_manager_endpoint.tf)

# *** The following PrivateLink Interface endpoints are only needed here, Layer 4, so we keep them here ***

# ECR API: for ECS to describe images
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [var.endpoints_sg_id]
  subnet_ids          = var.app_subnet_ids # This has 3 subnets so we are using 3 ENIs, one in each subnet
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ecr-api-endpoint"
  })
}

# ECR docker: For actually pulling the image layers
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [var.endpoints_sg_id]
  subnet_ids          = var.app_subnet_ids # This has 3 subnets so we are using 3 ENIs, one in each subnet
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ecr-dkr-endpoint"
  })
}

# CloudWatch Logs VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.app_subnet_ids # This has 3 subnets so we are using 3 ENIs, one in each subnet
  security_group_ids  = [var.endpoints_sg_id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-logs-endpoint"
  })
}
