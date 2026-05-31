output "control_plane_asg_name" {
  description = "Name of the Control Plane Auto Scaling Group"
  value       = aws_autoscaling_group.rr_k3s_cp_asg.name
}

output "worker_frontend_asg_name" {
  description = "Name of the Frontend Worker Auto Scaling Group"
  value       = aws_autoscaling_group.rr_k3s_worker_frontend_asg.name
}

output "worker_backend_asg_name" {
  description = "Name of the Backend Worker Auto Scaling Group"
  value       = aws_autoscaling_group.rr_k3s_worker_backend_asg.name
}

output "control_plane_nlb_dns" {
  description = "DNS name of the Internal NLB routing to the Control Plane"
  value       = aws_lb.rr_k3s_cp_nlb.dns_name
}