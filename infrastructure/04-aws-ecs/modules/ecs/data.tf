data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_secretsmanager_secret" "rr_db_secret" {
  name = "rr-${var.environment}-db-secret"
}