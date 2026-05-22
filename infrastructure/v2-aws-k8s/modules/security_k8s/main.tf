# ==========================================
# 1. Security Group "Shells"
# ==========================================

resource "aws_security_group" "rr_k8s_control_plane_sg" {
    name = "rr-${var.environment}-k8s-control-plane-sg"
    description = "Security group for k3s control plane"
    vpc_id = var.vpc_id

    tags = merge(var.common_tags, {
        Name = "rr-${var.environment}-k8s-control-plane-sg"
    })
}


resource "aws_security_group" "rr_k8s_worker_sg" {
    name = "rr-${var.environment}-k8s-worker-sg"
    description = "Security group for k3s worker nodes"
    vpc_id = var.vpc_id

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
    type = "ingress"
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
    security_group_id = aws_security_group.rr_k8s_control_plane_sg.id

    # TARGETED: Only instances with the worker security group can enter
    source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
    description = "K8s API Server access Only from K3s worker nodes"
}

# Rule B (Optional/self): Allow the Control plane to talk to itself over 6443
# (Required for local cluster loopback operations and multi-master setups)
resource "aws_security_group_rule" "rr_cp_ingress_api_self" {
    type = "ingress"
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
    security_group_id = aws_security_group.rr_k8s_control_plane_sg.id

    source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
    description = "Allow control plane local loopback API access"
}

# Rule: Control plane requires outbound internet to fetch images/updates
resource "aws_security_group_rule" "rr_cp_egress_all" {
    type = "egress"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
    description = "Allow all outbound"
}

# ==========================================
# 3. Worker Node Rules
# ==========================================

# Rule: Allow control plane to communicate with workers (Logs, Exec, Metrics)
resource "aws_security_group_rule" "rr_worker_ingress_from_cp" {
    type = "ingress"
    from_port = 0
    to_port = 0
    protocol = "-1"
    source_security_group_id = aws_security_group.rr_k8s_control_plane_sg.id
    security_group_id = aws_security_group.rr_k8s_worker_sg.id
    description = "Allow traffic from control plane"
}

# Rule: Allow workers to communicate with each other (Pod-to-Pod overlay network)
resource "aws_security_group_rule" "rr_worker_ingress_self" {
    type = "ingress"
    from_port = 0
    to_port = 0
    protocol = "-1"
    source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
    security_group_id = aws_security_group.rr_k8s_worker_sg.id
    description = "Allow inter-node worker traffic"
}

# Rule: Istio HTTP Gateway (Open to VPC so V1 ECS/ALB) can route canary traffic)
resource "aws_security_group_rule" "rr_worker_ingress_http" {
    type = "ingress"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["10.16.0.0/16"]
    security_group_id = aws_security_group.rr_k8s_worker_sg
    description = "HTTP for Istio Ingress Gateway from VPC"
}

