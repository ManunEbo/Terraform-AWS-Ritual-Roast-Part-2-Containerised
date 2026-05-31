resource "aws_security_group" "rr_k8s_worker_frontend_sg" {
  name        = "rr-${var.environment}-k8s-worker-frontend-sg"
  description = "Security group for k3s frontend worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-worker-frontend-sg"
  })
}

# Istio HTTP Ingress from Public ALB
resource "aws_security_group_rule" "rr_frontend_ingress_http_alb" {
  description              = "HTTP Ingress strictly from V1 Public ALB"
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = var.alb_sg_id
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
}

# Allow Control Plane to reach Kubelet
resource "aws_security_group_rule" "rr_frontend_ingress_from_cp" {
  description              = "Allow Control Plane to reach Worker Kubelet API"
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
}

# Calico Overlay to Control Plane
resource "aws_security_group_rule" "rr_cp_ingress_calico_bgp_frontend" {
  description              = "Allow Frontend Calico BGP to Control Plane"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
}

resource "aws_security_group_rule" "rr_cp_ingress_calico_vxlan_frontend" {
  description              = "Allow Frontend Calico VXLAN to Control Plane"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
}

# Allow Frontend Inter-Node Pod Communication
resource "aws_security_group_rule" "rr_frontend_ingress_self" {
  description              = "Allow inter-node Frontend traffic"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
}

resource "aws_security_group_rule" "rr_frontend_egress_all" {
  description       = "Allow all outbound"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
}

# Inject Egress rules into ALB to route to Frontend Workers
resource "aws_security_group_rule" "rr_alb_egress_to_frontend_http" {
  description              = "Allow public ALB to route HTTP traffic to Frontend Workers"
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
  security_group_id        = var.alb_sg_id
}