# ==========================================
# Auto-Generated K3s Cluster Join Token
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