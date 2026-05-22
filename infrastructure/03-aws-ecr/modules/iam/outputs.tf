output "frontend_github_role_arn" {
  value = aws_iam_role.rr_github_frontend_role.arn
}

output "backend_github_role_arn" {
  value = aws_iam_role.rr_github_backend_role.arn
}