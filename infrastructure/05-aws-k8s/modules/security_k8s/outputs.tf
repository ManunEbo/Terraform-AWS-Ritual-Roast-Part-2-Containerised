output "control_plane_sg_id" {
  description = "Security Group ID for the Control Plane"
  value       = aws_security_group.rr_k8s_control_plane_sg.id
}

output "worker_frontend_sg_id" {
  description = "Security Group ID for the Frontend Worker Nodes"
  value       = aws_security_group.rr_k8s_worker_frontend_sg.id
}

output "worker_backend_sg_id" {
  description = "Security Group ID for the Backend Worker Nodes"
  value       = aws_security_group.rr_k8s_worker_backend_sg.id
}