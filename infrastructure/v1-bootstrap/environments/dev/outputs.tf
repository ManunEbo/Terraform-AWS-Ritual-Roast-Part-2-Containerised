#--------------------------------------------------------------
# Tier 0 Outputs: The GitHub Actions Bridge
#--------------------------------------------------------------

output "frontend_ecr_url" {
  description = "The URL of the Frontend ECR Repository"
  value       = module.ecr.frontend_repo_url
}

output "backend_ecr_url" {
  description = "The URL of the Backend ECR Repository"
  value       = module.ecr.backend_repo_url
}

output "frontend_github_role_arn" {
  description = "The IAM Role ARN for GitHub Actions (Frontend)"
  value       = module.iam.frontend_github_role_arn
}

output "backend_github_role_arn" {
  description = "The IAM Role ARN for GitHub Actions (Backend)"
  value       = module.iam.backend_github_role_arn
}