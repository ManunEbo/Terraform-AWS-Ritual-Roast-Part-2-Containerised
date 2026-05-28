#--------------------------------------------------------------
# 4. Backend-SG: The backend security group
#--------------------------------------------------------------
resource "aws_security_group" "rr_backend" {
  name        = "rr-${var.environment}-backend-sg"
  description = "Backend containers (App Tier)"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-sg"
  })
}

# Ingress: Internal ALB -> Backend (Port 5000)
resource "aws_security_group_rule" "backend_from_internal_alb" {
  type                     = "ingress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_backend.id
  source_security_group_id = aws_security_group.rr_internal_alb.id
}

# Egress: Backend -> Database (3306)
resource "aws_security_group_rule" "backend_to_db" {
  type                     = "egress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_backend.id
  source_security_group_id = data.aws_security_group.database_sg.id 
}

# Egress: Backend -> Interface Endpoints (ECR/Secrets)
resource "aws_security_group_rule" "rr_backend_egress_to_endpoints" {
  description              = "RR: Allow Backend to pull from ECR and fetch Secrets"
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_backend.id
  source_security_group_id = aws_security_group.rr_endpoints_sg.id
}

# Egress: Backend -> S3 Gateway (Image Layers)
resource "aws_security_group_rule" "rr_backend_egress_to_s3" {
  description       = "RR: Allow Backend to pull image layers from S3"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.rr_backend.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
}