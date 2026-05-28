output "alb_sg_id" {
  description = "The Public edge load balancer security identifier"
  value       = aws_security_group.rr_alb.id
}
