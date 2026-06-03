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

# =========================================================
# ISTIO MUTATING WEBHOOK
# =========================================================
resource "aws_security_group_rule" "rr_frontend_ingress_istio_webhook" {
  description              = "Allow Control Plane to reach Istio Webhook for Sidecar Injection"
  type                     = "ingress"
  from_port                = 15017
  to_port                  = 15017
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
}

# =========================================================
# CALICO OVERLAY: CP RECEIVING FROM FRONTEND
# =========================================================
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

# =========================================================
# CALICO OVERLAY: FRONTEND RECEIVING FROM CP
# =========================================================
resource "aws_security_group_rule" "rr_frontend_ingress_calico_bgp_cp" {
  description              = "Allow Control Plane Calico BGP to Frontend"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

resource "aws_security_group_rule" "rr_frontend_ingress_calico_vxlan_cp" {
  description              = "Allow Control Plane Calico VXLAN to Frontend"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# =========================================================
# CALICO OVERLAY: FRONTEND RECEIVING FROM BACKEND
# =========================================================
resource "aws_security_group_rule" "rr_frontend_ingress_calico_bgp_backend" {
  description              = "Allow Backend Calico BGP to Frontend"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

resource "aws_security_group_rule" "rr_frontend_ingress_calico_vxlan_backend" {
  description              = "Allow Backend Calico VXLAN to Frontend"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_worker_frontend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
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

# =========================================================
# HARDENED ZERO-TRUST EGRESS 
# =========================================================

# 1. Internal VPC Trust Zone
resource "aws_security_group_rule" "rr_frontend_egress_vpc" {
  description       = "Allow all outbound traffic strictly within the VPC boundaries"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [data.aws_vpc.current.cidr_block]
  security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
}

# 2. External Web Trust Zone
resource "aws_security_group_rule" "rr_frontend_egress_https" {
  description       = "Allow HTTPS outbound for GHCR image pulls and Grafana telemetry"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
}

resource "aws_security_group_rule" "rr_frontend_egress_http" {
  description       = "Allow HTTP outbound for linux package updates and K3s dependencies"
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
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