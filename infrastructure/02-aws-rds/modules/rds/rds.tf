#--------------------------------------------------------------
# 1. Database Subnet Group
#--------------------------------------------------------------
resource "aws_db_subnet_group" "rr_db_subnet_group" {
  name       = "rr-${var.environment}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-db-subnet-group"
  })
}

#--------------------------------------------------------------
# 2. RDS MySQL Instance
#--------------------------------------------------------------
resource "aws_db_instance" "rr_database" {
  identifier = "rr-${var.environment}-db"
  db_name    = "ritual_roast"

  engine         = "mysql"
  engine_version = "8.4"

  # Fail creation instead of silently enrolling in paid RDS Extended Support
  # once this major version passes end of standard support.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  # High availability for the "Fortress"
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.rr_db_subnet_group.name
  vpc_security_group_ids = [var.database_sg_id]

  # Dynamic credentials
  # FIXED: Name matches the data source in secrets.tf
  username = jsondecode(data.aws_secretsmanager_secret_version.rr_latest_creds.secret_string)["username"]
  password = jsondecode(data.aws_secretsmanager_secret_version.rr_latest_creds.secret_string)["password"]

  skip_final_snapshot = true

  # FIXED: Reference the actual resource in secrets.tf, not a variable
  depends_on = [aws_secretsmanager_secret_version.rr_db_skeleton]

  lifecycle {
    # Critical: Prevent terraform from overwriting the password
    # once the lambda rotation begins its work.
    ignore_changes = [password]
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-db"
  })
}