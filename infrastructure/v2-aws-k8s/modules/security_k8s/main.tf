# ==========================================
# 1. K3s Control Plane Security Group
# ==========================================
resource "aws_security_group" "rr_k8s_control_plane_sg" {
  name        = "rr-${var.environment}-k8s-control-plane-sg"
  description = "Security group for K3s Control Plane"
  vpc_id      = var.vpc_id

  # Allow K8s API access (Port 6443) from within the VPC
  ingress {
    description = "K8s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.16.0.0/16"] 
  }

  # Allow all outbound traffic (Needed to pull images)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-control-plane-sg"
  })
}

# ==========================================
# 2. K3s Worker Node Security Group
# ==========================================
resource "aws_security_group" "rr_k8s_worker_sg" {
  name        = "rr-${var.environment}-k8s-worker-sg"
  description = "Security group for K3s Worker Nodes"
  vpc_id      = var.vpc_id

  # Allow all internal communication between worker nodes and control plane
  ingress {
    description = "Allow all internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.16.0.0/16"] 
  }

  # Allow HTTP Ingress for Istio Gateway
  ingress {
    description = "HTTP for Istio Ingress Gateway"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.16.0.0/16"] 
  }

  # Allow HTTPS Ingress for Istio Gateway
  ingress {
    description = "HTTPS for Istio Ingress Gateway"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.16.0.0/16"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-worker-sg"
  })
}

# ==========================================
# 3. Modify V1 RDS Security Group
# ==========================================
# This injects a rule into the V1 RDS Security Group to allow K8s workers to connect to MySQL
resource "aws_security_group_rule" "rr_rds_allow_k8s" {
  type                     = "ingress"
  from_port                = 3306 
  to_port                  = 3306 
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rr_k8s_worker_sg.id
  security_group_id        = var.rds_sg_id
  description              = "Allow traffic from K3s worker nodes to MySQL"
}