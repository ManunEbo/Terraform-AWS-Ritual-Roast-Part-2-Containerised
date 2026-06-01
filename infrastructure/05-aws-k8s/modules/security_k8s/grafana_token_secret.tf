# ==========================================
# Grafana Token (From Environment Variable)
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