data "aws_vpc" "current" {
  id = var.vpc_id
}

resource "aws_security_group" "rr_k8s_control_plane_sg" {
  name        = "rr-${var.environment}-k8s-control-plane-sg"
  description = "Security group for k3s control plane"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-control-plane-sg"
  })
}

# Allow VPC traffic (NLB Health Checks & Worker joining)
resource "aws_security_group_rule" "rr_cp_ingress_api_from_vpc" {
  description       = "Allow VPC CIDR to reach API Server"
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.current.cidr_block]
  security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# Calico BGP Loopback
resource "aws_security_group_rule" "rr_cp_ingress_calico_bgp_self" {
  description              = "Allow Calico BGP local loopback"
  type                     = "ingress"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

# Calico VXLAN Loopback
resource "aws_security_group_rule" "rr_cp_ingress_calico_vxlan_self" {
  description              = "Allow Calico VXLAN overlay network local loopback"
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.rr_k8s_control_plane_sg.id
  source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
}

resource "aws_security_group_rule" "rr_cp_egress_all" {
  description       = "Allow all outbound"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_k8s_control_plane_sg.id    
}