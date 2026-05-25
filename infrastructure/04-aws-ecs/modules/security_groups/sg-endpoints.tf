#--------------------------------------------------------------
# 7. Endpoints-SG: The AWS Service Entrance
#--------------------------------------------------------------
# This is the final piece of the "Fortress" networking logic.
# The Endpoint Security Group acts as a private listener for AWS services within the VPC.
# Because we aren't using a NAT Gateway, this SG is the only way the private resources
# (App and Lambda) can talk to the Secrets Manager, ECS, and ECR APIs.
# It sits on the "receiving" end of all those internal HTTPS calls.

resource "aws_security_group" "rr_endpoints_sg" {
  name_prefix = "rr-${var.environment}-vpc-endpoints-sg-"
  description = "RR: Receiving HTTPS traffic for VPC Interface Endpoints"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-vpc-endpoints-sg"
  })
}

# Rule 1: Identity - Backend Tier
resource "aws_security_group_rule" "rr_endpoints_ingress_from_backend" {
  type                     = "ingress"
  description              = "RR: Auth only for Backend containers (ECR/Secrets)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_endpoints_sg.id
  source_security_group_id = aws_security_group.rr_backend.id
}

# Rule 2: Identity - Lambda Tier
resource "aws_security_group_rule" "rr_endpoints_ingress_from_lambda" {
  type                     = "ingress"
  description              = "RR: Auth only for Rotation Lambda (Secrets API)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_endpoints_sg.id
  source_security_group_id = aws_security_group.rr_lambda.id # <----- This needs to be retrieved via data source
}

# Rule 3: Identity - Frontend Tier
resource "aws_security_group_rule" "rr_endpoints_ingress_from_frontend" {
  type                     = "ingress"
  description              = "RR: Auth only for Frontend containers (ECR)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_endpoints_sg.id
  source_security_group_id = aws_security_group.rr_frontend.id
}