#--------------------------------------------------------------
# 2. frontend-SG: The Web server Security Group
#--------------------------------------------------------------

resource "aws_security_group" "rr_frontend" {
  name        = "rr-${var.environment}-frontend-sg"
  description = "Frontend containers (Web Tier) security group"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-sg"
  })
}

# Ingress: Public ALB -> frontend (e.g. Port 3000)
resource "aws_security_group_rule" "rr_frontend_from_public_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_frontend.id
  source_security_group_id = data.aws_security_group.public_alb_sg.id
}

# Egress: Frontend -> Internal ALB (API Calls)
resource "aws_security_group_rule" "rr_frontend_to_internal_alb" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_frontend.id
  source_security_group_id = aws_security_group.rr_internal_alb.id
}

# Egress: Frontend -> Interface Endpoints (ECR/Logs)
resource "aws_security_group_rule" "rr_frontend_egress_to_endpoints" {
  description              = "RR: Allow Frontend to pull from ECR and write Logs"
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_frontend.id
  source_security_group_id = data.aws_security_group.rr_endpoints_sg.id
}

# Egress: Frontend -> S3 Gateway (Image Layers)
resource "aws_security_group_rule" "rr_frontend_egress_to_s3" {
  description       = "RR: Allow Frontend to pull image layers from S3"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.rr_frontend.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
}

# -------------------------------------------------------------------------
# INJECTED BACK INTO LAYER 1: Public ALB -> Frontend (Web Tier)
# -------------------------------------------------------------------------
resource "aws_security_group_rule" "alb_allow_outbound_to_frontend" {
  description = "RR: Retroactively injected by Layer 4 to allow ALB Egress"
  type        = "egress"
  from_port   = 3000
  to_port     = 3000
  protocol    = "tcp"

  # 1. The Security Group being modified (The ALB from Layer 1)
  security_group_id = data.aws_security_group.public_alb_sg.id

  # 2. The destination it is allowed to reach (The Frontend in Layer 4)
  source_security_group_id = aws_security_group.rr_frontend.id
}