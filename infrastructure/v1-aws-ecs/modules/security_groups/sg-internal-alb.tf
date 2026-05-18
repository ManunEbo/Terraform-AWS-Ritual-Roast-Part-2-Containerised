#--------------------------------------------------------------
# 3. Internal_ALB-SG: The internal ALB Security Group
#--------------------------------------------------------------
# This SG shields the backend from the frontend
# It allows the Frontend containers to forward path based
# requests to be handled by the backend
resource "aws_security_group" "rr_internal_alb" {
  name   = "rr-${var.environment}-internal-alb-sg"
  vpc_id = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.vpc_name}-internal-alb-sg"
  })
}

# Ingress: Frontend -> Internal ALB
resource "aws_security_group_rule" "rr_int_alb_from_frontend" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_internal_alb.id
  source_security_group_id = aws_security_group.rr_frontend.id
}

# Egress: internal ALB -> Backend
resource "aws_security_group_rule" "int_alb_to_backend" {
  type                     = "egress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_internal_alb.id
  source_security_group_id = aws_security_group.rr_backend.id
}