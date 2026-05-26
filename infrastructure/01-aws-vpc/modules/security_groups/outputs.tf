output "alb_sg_id" {
  description = "The Public edge load balancer security identifier"
  value       = aws_security_group.rr_alb.id
}

output "internal_alb_sg_id" {
  description = "The internal web-to-app tier routing security identifier"
  value       = aws_security_group.rr_internal_alb.id
}

output "frontend_sg_id" {
  description = "The Frontend tier runtime context identifier"
  value       = aws_security_group.rr_frontend.id
}

output "backend_sg_id" {
  description = "The Core Application tier runtime context identifier"
  value       = aws_security_group.rr_backend.id
}

output "database_sg_id" {
  description = "The persistent storage platform access identifier shell"
  value       = aws_security_group.rr_database.id
}

output "lambda_sg_id" {
  description = "The automated data engine rotation runtime identity"
  value       = aws_security_group.rr_lambda.id
}

output "endpoints_sg_id" {
  description = "The private boundary identity for secure cloud service endpoints"
  value       = aws_security_group.rr_endpoints.id
}