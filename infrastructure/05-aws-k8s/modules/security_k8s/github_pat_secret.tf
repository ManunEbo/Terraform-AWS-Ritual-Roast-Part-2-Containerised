# ==========================================
# GitHub PAT (From Environment Variable)
# ==========================================
resource "aws_secretsmanager_secret" "rr_github_pat" {
  name                    = "rr-${var.environment}-argocd-github-token"
  recovery_window_in_days = 0
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-argocd-github-token"
  })
}

resource "aws_secretsmanager_secret_version" "rr_github_pat_val" {
  secret_id     = aws_secretsmanager_secret.rr_github_pat.id
  secret_string = var.github_pat
}