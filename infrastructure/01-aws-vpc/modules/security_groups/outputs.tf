output "alb_sg_id" {
  description = "The Public edge load balancer security identifier"
  value       = aws_security_group.rr_alb.id
}

output "endpoints_sg_id" {
  description = "The ID of the VPC Endpoints Security Group"
  value       = aws_security_group.rr_endpoints_sg.id
}