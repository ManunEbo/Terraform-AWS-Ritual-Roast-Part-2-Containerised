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

# --- New Variables Required for K8s ---

variable "control_plane_type" {
  description = "EC2 instance type for the K3s Control Plane"
  type        = string
  default     = "t3.small" 
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
  description = "Grafana Cloud Token for Observability"
  type        = string
  sensitive   = true
  default     = "PENDING_TOKEN"
}