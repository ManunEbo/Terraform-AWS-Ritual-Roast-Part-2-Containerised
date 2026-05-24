output "database_sg" {
  description = "The Database Security Group object"
  value       = aws_security_group.rr_database
}

output "lambda_sg" {
  description = "The Lambda Rotation Security Group object"
  value       = aws_security_group.rr_lambda
}
