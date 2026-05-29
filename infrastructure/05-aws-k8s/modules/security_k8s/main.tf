# ==========================================
# 1. Security Group "Shells"
# ==========================================

resource "aws_security_group" "rr_k8s_control_plane_sg" {
  name        = "rr-${var.environment}-k8s-control-plane-sg"
  description = "Security group for k3s control plane"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-control-plane-sg"
  })
}

resource "aws_security_group" "rr_k8s_worker_sg" {
  name        = "rr-${var.environment}-k8s-worker-sg"
  description = "Security group for k3s worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-worker-sg"
  })
}

# ==========================================
# 2. Control Plane Rules
# Hardened Control Plane API Server Ingress
# ==========================================

# Rule A: Only allow authorized K3s worker nodes to talk to the API Server
resource "aws_security_group_rule" "rr_cp_ingress_api_from_workers" {
  description              = "K8s API Server access Only from K3s worker nodes"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id

  # TARGETED: Only instances with the worker security group can enter
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
}

# Rule B (Optional/self): Allow the Control plane to talk to itself over 6443
# (Required for local cluster loopback operations and multi-master setups)
resource "aws_security_group_rule" "rr_cp_ingress_api_self" {
  description              = "Allow control plane local loopback API access"
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# Rule C1: Allow Calico BGP networking from Workers
resource "aws_security_group_rule" "rr_cp_ingress_calico_bgp_from_workers" {
  description              = "Allow Calico BGP routing from workers"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
}

# Rule C2: Allow Calico BGP networking to talk to itself (Multi-Master)
resource "aws_security_group_rule" "rr_cp_ingress_calico_bgp_self" {
  description              = "Allow Calico BGP local loopback"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# Rule D1: Allow Calico VXLAN overlay network from Workers
resource "aws_security_group_rule" "rr_cp_ingress_calico_vxlan_from_workers" {
  description              = "Allow Calico VXLAN overlay network from workers"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
}

# Rule D2: Allow Calico VXLAN overlay network to talk to itself (Multi-Master)
resource "aws_security_group_rule" "rr_cp_ingress_calico_vxlan_self" {
  description              = "Allow Calico VXLAN overlay network local loopback"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# Rule E: Control plane requires outbound internet to fetch images/updates
resource "aws_security_group_rule" "rr_cp_egress_all" {
  description       = "Allow all outbound"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_control_plane_sg.id    
}

# ==========================================
# 3. Worker Node Rules (Zero-Trust Ingress)
# ==========================================

# BUG 2 FIX: Locked down to Kubelet API port 10250 instead of blanket "-1"
resource "aws_security_group_rule" "rr_worker_ingress_from_cp" {
  description              = "Allow Control Plane to reach Worker Kubelet API (Logs/Exec/Metrics)"
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_sg.id
}

# Allow Workers to communicate with each other (Pod-to-pod overlay network)
resource "aws_security_group_rule" "rr_worker_ingress_self" {
  description              = "Allow inter-node Worker traffic"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_sg.id
}

# Istio HTTP Gateway - LOCKED exclusively to the Public ALB
resource "aws_security_group_rule" "rr_worker_ingress_http_alb" {
  description              = "HTTP Ingress strictly from V1 Public ALB"
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = var.alb_sg_id
  security_group_id        = aws_security_group.rr_k8s_worker_sg.id
}

# Istio HTTPS Gateway - LOCKED exclusively to the Public ALB
resource "aws_security_group_rule" "rr_worker_ingress_https_alb" {
  description              = "HTTPS Ingress strictly from public ALB"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = var.alb_sg_id
  security_group_id        = aws_security_group.rr_k8s_worker_sg.id
}

# Workers require outbound internet to fetch GHCR images and route NAT traffic
resource "aws_security_group_rule" "rr_worker_egress_all" {
  description       = "Allow all outbound"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_worker_sg.id
}

# ==========================================
# 4. External Layer Wiring (ALB & RDS)
# ==========================================

# Inject an egress rule into the public ALB so it can route HTTP traffic to K8s Workers
resource "aws_security_group_rule" "rr_alb_egress_to_k8s_http" {
  description              = "Allow public ALB to route HTTP traffic to K3s worker Nodes"
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
  security_group_id        = var.alb_sg_id
}

# BUG 3 FIX: Inject an egress rule into the public ALB for HTTPS routing (Asymmetric routing fix)
resource "aws_security_group_rule" "rr_alb_egress_to_k8s_https" {
  description              = "Allow public ALB to route HTTPS traffic to K3s worker Nodes"
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
  security_group_id        = var.alb_sg_id
}

# BUG 1 FIX: Allow Worker Nodes to communicate with the Layer 2 Database
resource "aws_security_group_rule" "rr_rds_ingress_from_k8s_workers" {
  description              = "Allow K3s worker nodes to access the RDS Database"
  type                     = "ingress"
  from_port                = 5432 # (Ensure this matches your database engine port, e.g., 5432 for Postgres)
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
  security_group_id        = var.rds_sg_id
}