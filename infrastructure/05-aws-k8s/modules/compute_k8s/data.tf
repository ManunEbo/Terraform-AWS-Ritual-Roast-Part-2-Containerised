# Fetch the latest Amazon Linux 2023 AMI (Shared across the compute module)
data "aws_ami" "rr_al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_secretsmanager_secret" "rr_db_secret" {
  # This dynamically targets the exact secret name based on the environment
  name = "rr-${var.environment}-db-secret"
}