#--------------------------------------------------------------
# 1. The Secret Container
#--------------------------------------------------------------
resource "aws_secretsmanager_secret" "rr_db_secret" {
  name                    = "rr-${var.environment}-db-secret"
  description             = "Database credentials for Ritual Roast (${var.environment})"
  recovery_window_in_days = 0 # Set to 7+ for production!

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-db-secret"
  })
}

#--------------------------------------------------------------
# 2. STAGE 1: Skeleton Version (Initial Credentials)
#--------------------------------------------------------------
# Allows RDS to provision before it has a host address.
resource "aws_secretsmanager_secret_version" "rr_db_skeleton" {
  secret_id = aws_secretsmanager_secret.rr_db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = "placeholder"
    port     = 3306
    dbname   = "ritual_roast"
  })
}

#--------------------------------------------------------------
# 3. THE DYNAMIC POINTER
#--------------------------------------------------------------
# Tracks the "AWSCURRENT" label so ECS and RDS always have the latest.
data "aws_secretsmanager_secret_version" "rr_latest_creds" {
  secret_id = aws_secretsmanager_secret.rr_db_secret.id

  # Ensure the skeleton exists so the data source doesn't fail on first run
  depends_on = [aws_secretsmanager_secret_version.rr_db_skeleton]
}

#--------------------------------------------------------------
# 4. STAGE 2: Full Version (Injecting the RDS Host)
#--------------------------------------------------------------
resource "aws_secretsmanager_secret_version" "rr_db_host_update" {
  secret_id = aws_secretsmanager_secret.rr_db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    dbname   = "ritual_roast"
    port     = 3306
    host     = aws_db_instance.rr_database.address
  })

  # Ensure the rds instance is active and has an address before updating
  depends_on = [aws_db_instance.rr_database]

  lifecycle {
    # Prevents terraform from reverting rotated passwords
    # once the rotation lambda (with its layers) changes the password,
    # terraform must ignore the 'secret_string' to avoid a rollback.
    ignore_changes = [secret_string]
  }
}

#--------------------------------------------------------------
# 5. Rotation Logic (Triggering the Layered Lambda)
#--------------------------------------------------------------
resource "aws_secretsmanager_secret_rotation" "rr_db_rotation" {
  secret_id           = aws_secretsmanager_secret.rr_db_secret.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 7 # the standard rotation window is 30 days
  }

  # Only begin rotation once the full host information is in the secret
  depends_on = [aws_secretsmanager_secret_version.rr_db_host_update]
}