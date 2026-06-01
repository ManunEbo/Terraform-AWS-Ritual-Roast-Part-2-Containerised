# ==========================================
# 1. Auto-Generated K3s Cluster Join Token
# ==========================================
resource "random_password" "k3s_join_token" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "rr_k3s_join_token" {
  name                    = "rr-${var.environment}-k3s-join-token"
  recovery_window_in_days = 0
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-join-token"
  })
}

resource "aws_secretsmanager_secret_version" "rr_k3s_join_token_val" {
  secret_id     = aws_secretsmanager_secret.rr_k3s_join_token.id
  secret_string = random_password.k3s_join_token.result
}

# ==========================================
# 2. GitHub PAT (From Environment Variable)
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

# ==========================================
# 3. Grafana Token (From Environment Variable)
# ==========================================
resource "aws_secretsmanager_secret" "rr_grafana_token" {
  name                    = "rr-${var.environment}-grafana-cloud-token"
  recovery_window_in_days = 0
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-grafana-cloud-token"
  })
}

resource "aws_secretsmanager_secret_version" "rr_grafana_token_val" {
  secret_id     = aws_secretsmanager_secret.rr_grafana_token.id
  secret_string = var.grafana_token
}