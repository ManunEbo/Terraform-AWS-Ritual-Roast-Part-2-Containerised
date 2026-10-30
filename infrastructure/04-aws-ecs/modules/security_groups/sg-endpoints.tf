#--------------------------------------------------------------
# 7. Endpoints-SG: The AWS Service Entrance
#--------------------------------------------------------------
# This is the final piece of the "Fortress" networking logic.
# The Endpoint Security Group acts as the guard of private listeners for AWS services within the VPC.
# Because we aren't using a NAT Gateway, the interface endpoints are the only way the private resources
# (App and Lambda) can talk to the Secrets Manager, ECS, and ECR APIs. The endpoints SG is their firewall.
# It sits on the "receiving" end of all those internal HTTPS calls.


# # Rule 1: Identity - Frontend Tier
resource "aws_security_group_rule" "rr_endpoints_ingress_from_frontend" {
  type                     = "ingress"
  description              = "RR: Auth only for Frontend containers (ECR)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.rr_endpoints_sg.id
  source_security_group_id = aws_security_group.rr_frontend.id
}

# Rule 2: Identity - Backend Tier
resource "aws_security_group_rule" "rr_endpoints_ingress_from_backend" {
  type                     = "ingress"
  description              = "RR: Auth only for Backend containers (ECR/Secrets)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.rr_endpoints_sg.id
  source_security_group_id = aws_security_group.rr_backend.id
}