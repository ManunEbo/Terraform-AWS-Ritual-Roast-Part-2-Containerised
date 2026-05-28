output "internal_alb_dns_name" {
  description = "The internal DNS name for the Backend API"
  value       = aws_lb.internal.dns_name # Here we are outputing the dns_name instead of id
}

output "frontend_tg_arn" {
  description = "The ARN of the Frontend Target Group for ECS"
  value       = aws_lb_target_group.rr_frontend.arn
}

output "backend_tg_arn" {
  description = "The ARN of the backend Target group for ECS"
  value       = aws_lb_target_group.backend.arn
}