
# Secrets Manager: For lambda rotation and App secret retrieval
# Layer 4 version
# resource "aws_vpc_endpoint" "secretsmanager" {
#   vpc_id              = var.vpc_id
#   service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
#   vpc_endpoint_type   = "Interface"
#   security_group_ids  = [var.endpoints_sg_id]
#   subnet_ids          = var.app_subnet_ids
#   private_dns_enabled = true

#   tags = merge(var.common_tags, {
#     Name = "${var.environment}-secrets-endpoint"
#   })
# }

# Secrets Manager VPC Interface Endpoint
# Placed in the App Subnets to serve both ECS Tasks and Lambda Functions
# resource "aws_vpc_endpoint" "rr_secretsmanager" {
#   vpc_id              = var.vpc_id
#   service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
#   vpc_endpoint_type   = "Interface"

#   # 1. Attach the Security Group Shell we just created
#   security_group_ids  = [data.aws_security_group.rr_endpoints_sg.id]

#   # 2. Place in the shared middle-tier subnets
#   subnet_ids          = var.app_subnet_ids

#   # 3. CRITICAL: Allows boto3/AWS SDKs to use the endpoint automatically
#   private_dns_enabled = true

#   tags = merge(var.common_tags, {
#     Name = "rr-${var.environment}-secrets-endpoint"
#   })
# }

resource "aws_vpc_endpoint" "rr_secretsmanager" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  # SWAPPED: Now using the explicit variable
  security_group_ids = [var.endpoints_sg_id]

  subnet_ids          = var.app_subnet_ids
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-secrets-endpoint"
  })
}