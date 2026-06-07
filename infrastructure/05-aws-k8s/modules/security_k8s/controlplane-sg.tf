resource "aws_security_group" "rr_k8s_control_plane_sg" {
  name        = "rr-${var.environment}-k8s-control-plane-sg"
  description = "Security group for k3s control plane"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-control-plane-sg"
  })
}

# =========================================================
# ZERO-TRUST API SERVER ACCESS (PORT 6443)
# =========================================================

# 1. API Access from Frontend Workers
resource "aws_security_group_rule" "rr_cp_ingress_api_from_frontend" {
  description              = "Allow Frontend workers to reach API Server"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_frontend_sg.id
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
}

# 2. API Access from Backend Workers
resource "aws_security_group_rule" "rr_cp_ingress_api_from_backend" {
  description              = "Allow Backend workers to reach API Server"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
}

# 3. API Access for NLB Health Checks & Routing
resource "aws_security_group_rule" "rr_cp_ingress_api_from_nlb" {
  description              = "Allow Internal NLB to route traffic and health checks to API Server"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_nlb_sg.id 
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
}

# =========================================================
# UNIFIED CONTROL PLANE MESH (ETCD, CALICO, KUBELET)
# =========================================================
resource "aws_security_group_rule" "rr_cp_ingress_self" {
  description              = "Allow all inter-node Control Plane traffic for HA etcd and mesh"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
}

# =========================================================
# HARDENED ZERO-TRUST EGRESS 
# =========================================================

# 1. Internal VPC Trust Zone
resource "aws_security_group_rule" "rr_cp_egress_vpc" {
  description       = "Allow all outbound traffic strictly within the VPC boundaries"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [data.aws_vpc.current.cidr_block]
  security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# 2. External Web Trust Zone
resource "aws_security_group_rule" "rr_cp_egress_https" {
  description       = "Allow HTTPS outbound for K3s installation and external APIs"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

resource "aws_security_group_rule" "rr_cp_egress_http" {
  description       = "Allow HTTP outbound for linux package updates"
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# =========================================================
# ENDPOINT SG
# =========================================================

# INJECTED INGRESS: Let Control Plane into Layer 1 Endpoints SG (Port 443)
resource "aws_security_group_rule" "rr_endpoints_ingress_from_cp" {
  description              = "RR: Allow Control Plane to reach Secrets Manager via VPC Endpoint"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  
  # 1. The Target being modified (Layer 1)
  security_group_id        = var.endpoints_sg_id
  
  # 2. The Source allowed in (Layer 5)
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id 
}



# =========================================================
# CALICO OVERLAY: CP RECEIVING FROM WORKERS
# =========================================================

# 1. From Frontend
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

# 2. From Backend
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