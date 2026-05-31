resource "aws_security_group" "rr_k8s_worker_backend_sg" {
  name        = "rr-${var.environment}-k8s-worker-backend-sg"
  description = "Security group for k3s backend worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-worker-backend-sg"
  })
}

# Allow Frontend Pods to initiate connections to Backend Pods via Calico Overlay
resource "aws_security_group_rule" "rr_backend_ingress_from_frontend" {
  description              = "Allow traffic from Frontend workers"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
}

# Allow Control Plane to reach Kubelet
resource "aws_security_group_rule" "rr_backend_ingress_from_cp" {
  description              = "Allow Control Plane to reach Worker Kubelet API"
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
}

# Calico Overlay to Control Plane
resource "aws_security_group_rule" "rr_cp_ingress_calico_bgp_backend" {
  description              = "Allow Backend Calico BGP to Control Plane"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

resource "aws_security_group_rule" "rr_cp_ingress_calico_vxlan_backend" {
  description              = "Allow Backend Calico VXLAN to Control Plane"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

# Allow Backend Inter-Node Pod Communication
resource "aws_security_group_rule" "rr_backend_ingress_self" {
  description              = "Allow inter-node Backend traffic"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
}

resource "aws_security_group_rule" "rr_backend_egress_all" {
  description       = "Allow all outbound"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

# Inject Ingress rule into RDS to allow Backend connections
resource "aws_security_group_rule" "rr_rds_ingress_from_backend" {
  description              = "Allow K3s Backend nodes to access the RDS Database"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
  security_group_id        = var.rds_sg_id
}