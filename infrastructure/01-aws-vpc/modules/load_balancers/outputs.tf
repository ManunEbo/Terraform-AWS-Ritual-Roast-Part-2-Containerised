output "public_alb_dns_name" {
  description = "The public DNS name of the Load Balancer for accessing the Frontend"
  value       = aws_lb.public.dns_name
}

# This should be in 04-aws-ecs
# output "internal_alb_dns_name" {
#   description = "The internal DNS name for the Backend API"
#   value       = aws_lb.internal.dns_name
# }

output "frontend_tg_arn" {
  description = "The ARN of the Frontend Target Group for ECS"
  value       = aws_lb_target_group.rr_frontend.arn
}

# This should be in 04-aws-ecs
# output "backend_tg_arn" {
#   description = "The ARN of the backend Target group for ECS"
#   value       = aws_lb_target_group.backend.arn
# }