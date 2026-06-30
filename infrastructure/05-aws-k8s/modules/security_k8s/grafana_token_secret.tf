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

resource "aws_secretsmanager_secret" "rr_grafana_remote_write_url" {
  name                    = "rr-${var.environment}-grafana-remote-write-url"
  recovery_window_in_days = 0
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-grafana-remote-write-url"
  })
}

resource "aws_secretsmanager_secret_version" "rr_grafana_remote_write_url_val" {
  secret_id     = aws_secretsmanager_secret.rr_grafana_remote_write_url.id
  secret_string = var.grafana_remote_write_url
}

resource "aws_secretsmanager_secret" "rr_grafana_instance_id" {
  name                    = "rr-${var.environment}-grafana-instance-id"
  recovery_window_in_days = 0
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-grafana-instance-id"
  })
}

resource "aws_secretsmanager_secret_version" "rr_grafana_instance_id_val" {
  secret_id     = aws_secretsmanager_secret.rr_grafana_instance_id.id
  secret_string = var.grafana_instance_id
}