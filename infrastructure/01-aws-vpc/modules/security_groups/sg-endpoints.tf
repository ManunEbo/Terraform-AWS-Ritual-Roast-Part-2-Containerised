#--------------------------------------------------------------
# Endpoints-SG: The AWS Service Entrance (Layer 1 Base)
#--------------------------------------------------------------
resource "aws_security_group" "rr_endpoints_sg" {
  name_prefix = "rr-${var.environment}-vpc-endpoints-sg-"
  description = "RR: Base shell for VPC Interface Endpoints. Rules injected by upper layers."
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-vpc-endpoints-sg"
  })
}