#--------------------------------------------------------------
# rr-Database-SG: Base Structural Identity Shell
#--------------------------------------------------------------

# The Database SG is the most restricted layer. It operates on 
# a "Zero Trust" basis, only allowing ingress from the Backend 
# and the rotation Lambda.


resource "aws_security_group" "rr_database" {
  name_prefix = "rr-${var.environment}-database-sg-"
  description = "RR: Foundational security identity boundary for database assets"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-database-sg"
  })
}

#--------------------------------------------------------------
# Ingress Rules (MySQL Port 3306)
#--------------------------------------------------------------

# This security group rule will be attached in ECS as the rr_backend security group only exists when ECS is up
# resource "aws_security_group_rule" "rr_db_ingress_from_backend" {
#   type                     = "ingress"
#   description              = "RR: Backend containers access to MySQL"
#   from_port                = 3306
#   to_port                  = 3306
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.rr_database.id
#   source_security_group_id = aws_security_group.rr_backend.id # Referenced from sg-app-tier.tf
# }

resource "aws_security_group_rule" "rr_db_ingress_from_lambda" {
  type                     = "ingress"
  description              = "RR: Lambda rotation access to MySQL"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rr_database.id
  source_security_group_id = aws_security_group.rr_lambda.id # Referenced from sg-lambda.tf
}