resource "aws_security_group" "rr_k8s_nlb_sg" {
  name        = "rr-${var.environment}-k8s-nlb-sg"
  description = "Security group for the internal K3s API Network Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-nlb-sg"
  })
}

# =========================================================
# INGRESS: STRICTLY WORKER NODES
# =========================================================
resource "aws_security_group_rule" "rr_nlb_ingress_from_frontend" {
  description              = "Allow Frontend Workers to reach NLB"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
  security_group_id        = aws_security_group.rr_k8s_nlb_sg.id
}

resource "aws_security_group_rule" "rr_nlb_ingress_from_backend" {
  description              = "Allow Backend Workers to reach NLB"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
  security_group_id        = aws_security_group.rr_k8s_nlb_sg.id
}

# =========================================================
# EGRESS: ROUTE TO CONTROL PLANE
# =========================================================
resource "aws_security_group_rule" "rr_nlb_egress_to_cp" {
  description              = "Allow NLB to route traffic to Control Plane API"
  type                     = "egress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_nlb_sg.id
}