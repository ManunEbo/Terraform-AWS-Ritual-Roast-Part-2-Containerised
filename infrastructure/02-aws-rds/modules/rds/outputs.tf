output "db_secret_arn" {
  description = "The ARN of the Secrets Manager secret holding the DB credentials"
  value       = aws_secretsmanager_secret.rr_db_secret.arn
}


output "db_instance_endpoint" {
  # Change 'rr_db' to 'rr_database'
  value = aws_db_instance.rr_database.endpoint
}