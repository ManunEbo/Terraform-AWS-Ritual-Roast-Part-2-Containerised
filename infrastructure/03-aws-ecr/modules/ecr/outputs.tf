output "frontend_repo_url" {
  value = aws_ecr_repository.rr_frontend_repo.repository_url
}

output "backend_repo_url" {
  value = aws_ecr_repository.rr_backend_repo.repository_url
}

output "frontend_repo_arn" {
  value = aws_ecr_repository.rr_frontend_repo.arn
}

output "backend_repo_arn" {
  value = aws_ecr_repository.rr_backend_repo.arn
}