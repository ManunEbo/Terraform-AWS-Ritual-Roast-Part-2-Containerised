#--------------------------------------------------------------
#               rr-Lambda-SG: The Admin/Rotation Tier
#--------------------------------------------------------------

# In this NAT-less architecture, the Lambda functions as a private operative.
# It reaches the Database to rotate passwords and reaches the Secrets Manager 
# API via VPC Endpoints to update them.

resource "aws_security_group" "rr_lambda" {
  name        = "rr-${var.environment}-lambda-sg"
  description = "RR: Allow Lambda to reach RDS and Secrets Manager VPC Endpoints"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-lambda-sg"
  })
}

# Egress: Lambda -> Database (MySQL Port 3306)
resource "aws_security_group_rule" "rr_lambda_egress_to_db" {
  type                     = "egress"
  description              = "RR: Allow Lambda to rotate DB credentials"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_lambda.id
  source_security_group_id = aws_security_group.rr_database.id
}

# Egress: Lambda -> VPC Endpoints (HTTPS Port 443)
resource "aws_security_group_rule" "rr_lambda_egress_to_endpoints" {
  type                     = "egress"
  description              = "RR: Allow Lambda to reach Secrets Manager via VPC Endpoint"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_lambda.id
  source_security_group_id = aws_security_group.rr_endpoints.id # Referenced from sg-endpoints.tf
}