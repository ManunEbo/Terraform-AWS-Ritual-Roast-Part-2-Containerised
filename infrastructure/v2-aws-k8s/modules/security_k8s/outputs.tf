output "control_plane_sg_id" {
  description = "Security Group ID for the Control Plane"
  value       = aws_security_group.rr_k8s_control_plane_sg.id
}

output "worker_node_sg_id" {
  description = "Security Group ID for the Worker Nodes"
  value       = aws_security_group.rr_k8s_worker_sg.id
}