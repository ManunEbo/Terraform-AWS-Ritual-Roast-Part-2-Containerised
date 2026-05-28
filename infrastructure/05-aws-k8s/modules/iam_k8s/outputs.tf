output "control_plane_profile_name" {
  description = "The IAM Instance Profile name for the Control Plane EC2 instance"
  value = aws_iam_instance_profile.rr_k3s_control_plane_profile.name
}

output "worker_profile_name" {
  description = "The IAM Instance Profile name for the Worker EC2 instance"
  value = aws_iam_instance_profile.rr_k3s_worker_profile.name
}