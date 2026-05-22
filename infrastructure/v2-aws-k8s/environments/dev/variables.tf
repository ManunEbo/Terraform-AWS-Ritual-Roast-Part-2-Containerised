variable "aws_region" {
  description = "The AWS region to deploy into"
  type        = string
  default     = "eu-west-2"
}

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


variable "k8s_subnet_list" {
  description = "The subnet list map for Kubernetes subnet"
  type = list(object({
    subnet_name = string
    cidr        = string
    az          = string
  }))
}