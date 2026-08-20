#--------------------------------------------------------------
# CloudWatch Log Groups
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "rr_frontend_logs" {
  name              = "/ecs/rr-${var.environment}-frontend"
  retention_in_days = 7
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-logs"
  })
}

resource "aws_cloudwatch_log_group" "rr_backend_logs" {
  name              = "/ecs/rr-${var.environment}-backend"
  retention_in_days = 7

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-logs"
  })
}