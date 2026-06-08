# ==========================================
# Core Infrastructure Variables
# ==========================================

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "aws_region" {
  description = "AWS Region for Secrets Manager retrieval"
  type        = string
  default     = "eu-west-2"
}

variable "common_tags" {
  description = "Common tags from shared locals"
  type        = map(string)
}

variable "environment" {
  description = "The deployment environment"
  type        = string
}

variable "k8s_private_subnets" {
  description = "List of private subnet IDs for the K8s cluster"
  type        = list(string)
}

variable "control_plane_type" {
  description = "EC2 instance type for the K3s Control Plane"
  type        = string
}

variable "worker_node_type" {
  description = "EC2 instance type for the K3s Worker Nodes"
  type        = string
}

# ==========================================
# Control Plane Identities
# ==========================================

variable "control_plane_sg_id" {
  description = "Security Group ID for the Control Plane"
  type        = string
}

variable "iam_profile_control_plane" {
  description = "IAM Instance Profile name for the Control Plane"
  type        = string
}

# ==========================================
# Frontend Worker Identities (DMZ)
# ==========================================

variable "worker_frontend_sg_id" {
  description = "Security Group ID for the Frontend Worker Nodes"
  type        = string
}

variable "iam_profile_worker_frontend" {
  description = "IAM Instance Profile name for the Frontend Worker Nodes"
  type        = string
}

# ==========================================
# Backend Worker Identities (Secure Tier)
# ==========================================

variable "worker_backend_sg_id" {
  description = "Security Group ID for the Backend Worker Nodes"
  type        = string
}

variable "iam_profile_worker_backend" {
  description = "IAM Instance Profile name for the Backend Worker Nodes"
  type        = string
}

variable "nlb_sg_id" {
  description = "Security Group ID for the Network Load Balancer"
  type        = string
}