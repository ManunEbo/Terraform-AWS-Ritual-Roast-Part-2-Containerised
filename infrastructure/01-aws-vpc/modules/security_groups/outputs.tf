output "alb_sg" {
  description = "The Public Load Balancer Security Group Object"
  value       = aws_security_group.rr_alb
}

output "internal_alb_sg" {
  description = "The internal loadbalancer security group object"
  value       = aws_security_group.rr_internal_alb
}

output "frontend_sg" {
  description = "The Frontend (Web Tier) Security Group object"
  value       = aws_security_group.rr_frontend
}

output "backend_sg" {
  description = "The Backend (App Tier) Security Group object"
  value       = aws_security_group.rr_backend
}

output "database_sg" {
  description = "The Database Security Group object"
  value       = aws_security_group.rr_database
}

output "lambda_sg" {
  description = "The Lambda Rotation Security Group object"
  value       = aws_security_group.rr_lambda
}

output "endpoints_sg" {
  description = "The VPC Endpoints Security Group object"
  value       = aws_security_group.rr_endpoints
}