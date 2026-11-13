variable "environment" {
  description = "The deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "The AWS Region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_name" {
  type    = string
  default = "RR-vpc"
}

# --- New Variables Required for K8s ---

variable "control_plane_type" {
  description = "EC2 instance type for the K3s Control Plane"
  type        = string
  default     = "t3.medium"
}

variable "worker_node_type" {
  description = "EC2 instance type for the K3s Worker Nodes"
  type        = string
  default     = "t3.medium"
}

variable "github_pat" {
  description = "GitHub Personal Access Token for ArgoCD"
  type        = string
  sensitive   = true
}

variable "grafana_token" {
  description = "Grafana Cloud API token (bearer token)"
  type        = string
  sensitive   = true
}

variable "grafana_remote_write_url" {
  description = "Grafana Cloud Prometheus remote write URL"
  type        = string
  sensitive   = true
}

variable "grafana_instance_id" {
  description = "Grafana Cloud Prometheus instance ID (numeric)"
  type        = string
  sensitive   = true
}