
output "lambda_role_arn" {
  description = "The lambda role ARN"
  value       = aws_iam_role.rr_lambda_secrets_role.arn
}