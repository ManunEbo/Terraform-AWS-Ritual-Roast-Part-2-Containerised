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

# =========================================================
# ISTIO MUTATING WEBHOOK
# =========================================================
resource "aws_security_group_rule" "rr_backend_ingress_istio_webhook" {
  description              = "Allow Control Plane to reach Istio Webhook for Sidecar Injection"
  type                     = "ingress"
  from_port                = 15017
  to_port                  = 15017
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
}

# =========================================================
# CALICO OVERLAY MESH
# =========================================================
# resource "aws_security_group_rule" "rr_cp_ingress_calico_bgp_backend" {
#   description              = "Allow Backend Calico BGP to Control Plane"
#   type                     = "ingress"
#   from_port                = 179
#   to_port                  = 179
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
#   source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
# }

# resource "aws_security_group_rule" "rr_cp_ingress_calico_vxlan_backend" {
#   description              = "Allow Backend Calico VXLAN to Control Plane"
#   type                     = "ingress"
#   from_port                = 4789
#   to_port                  = 4789
#   protocol                 = "udp"
#   security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
#   source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
# }

resource "aws_security_group_rule" "rr_backend_ingress_calico_bgp_cp" {
  description              = "Allow Control Plane Calico BGP to Backend"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

resource "aws_security_group_rule" "rr_backend_ingress_calico_vxlan_cp" {
  description              = "Allow Control Plane Calico VXLAN to Backend"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
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

# Inject Ingress rule into RDS to allow Backend connections
resource "aws_security_group_rule" "rr_rds_ingress_from_backend" {
  description              = "Allow K3s Backend nodes to access the MySQL RDS Database"
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
  security_group_id        = var.rds_sg_id
}

# =========================================================
# HARDENED ZERO-TRUST EGRESS 
# =========================================================

# 1. Internal VPC Trust Zone
resource "aws_security_group_rule" "rr_backend_egress_vpc" {
  description       = "Allow all outbound traffic strictly within the VPC boundaries"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [data.aws_vpc.current.cidr_block]
  security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

# 2. External Web Trust Zone
resource "aws_security_group_rule" "rr_backend_egress_https" {
  description       = "Allow HTTPS outbound for GHCR image pulls and Grafana telemetry"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

resource "aws_security_group_rule" "rr_backend_egress_http" {
  description       = "Allow HTTP outbound for linux package updates and K3s dependencies"
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id
}

# =========================================================
# ENDPOINT SG - Backend
# =========================================================

# INJECTED INGRESS: Let Control Plane into Layer 1 Endpoints SG (Port 443)
resource "aws_security_group_rule" "rr_endpoints_ingress_from_wkr_backend" {
  description              = "RR: Allow Backend worker to reach Secrets Manager via VPC Endpoint"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  
  # 1. The Target being modified (Layer 1)
  security_group_id        = var.endpoints_sg_id
  
  # 2. The Source allowed in (Layer 5)
  source_security_group_id = aws_security_group.rr_k8s_worker_backend_sg.id 
}

# =========================================================
# CALICO TYPHA (PORT 5473)
# =========================================================
resource "aws_security_group_rule" "rr_backend_ingress_typha_cp" {
  description              = "Allow CP Calico Node to reach Typha on Backend"
  type                     = "ingress"
  from_port                = 5473
  to_port                  = 5473
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# =========================================================
# ZERO-TRUST OVERLAY FALLBACKS & METRICS
# =========================================================

# Protocol 4 (IPIP) from Control Plane
resource "aws_security_group_rule" "rr_backend_ingress_ipip_cp" {
  description              = "Allow Calico IPIP from Control Plane"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "4"
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# Metrics Server (CP scraping Workers)
resource "aws_security_group_rule" "rr_backend_ingress_metrics_cp" {
  description              = "Allow Control Plane to scrape Metrics Server"
  type                     = "ingress"
  from_port                = 4443
  to_port                  = 4443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_worker_backend_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}