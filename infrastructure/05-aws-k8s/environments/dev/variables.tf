variable "environment" {
  description = "The deployment environment"
  type        = string
  default     = "dev"
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
