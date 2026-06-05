#--------------------------------------------------------------
# 1. LoadBalancer-SG: The Front Door
#--------------------------------------------------------------
# This receives traffic from the internet on port 80 or 443
# and redirects it to the frontend containers
resource "aws_security_group" "rr_alb" {
  name        = "rr-${var.environment}-alb-sg"
  description = "Allow HTTP/HTTPS from the internet and outbound to Frontend containers"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-alb-sg"
  })
}

# Ingress: HTTP
resource "aws_security_group_rule" "rr_alb_allow_80_inbound" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_alb.id
}

# Ingress HTTPS: This is a must have for production
resource "aws_security_group_rule" "alb_allow_443_inbound" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_alb.id
}

