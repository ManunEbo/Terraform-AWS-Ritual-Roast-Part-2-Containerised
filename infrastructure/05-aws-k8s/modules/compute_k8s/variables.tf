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

variable "control_plane_sg_id" {
  description = "Security Group ID for the Control Plane"
  type        = string
}

variable "worker_sg_id" {
  description = "Security Group ID for the Worker Nodes"
  type        = string
}

variable "iam_profile_control_plane" {
  description = "IAM Instance Profile name for the Control Plane"
  type        = string
}

variable "iam_profile_worker" {
  description = "IAM Instance Profile name for the Worker Nodes"
  type        = string
}

variable "control_plane_type" {
  description = "EC2 instance type for the K3s Control Plane"
  type        = string
}

variable "worker_node_type" {
  description = "EC2 instance type for the K3s Worker Nodes"
  type        = string
}