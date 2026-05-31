output "control_plane_profile_name" {
  description = "IAM Instance Profile name for the Control Plane"
  value       = aws_iam_instance_profile.rr_k3s_cp_profile.name
}

output "worker_frontend_profile_name" {
  description = "IAM Instance Profile name for the Frontend Worker Nodes"
  value       = aws_iam_instance_profile.rr_k3s_worker_frontend_profile.name
}

output "worker_backend_profile_name" {
  description = "IAM Instance Profile name for the Backend Worker Nodes"
  value       = aws_iam_instance_profile.rr_k3s_worker_backend_profile.name
}