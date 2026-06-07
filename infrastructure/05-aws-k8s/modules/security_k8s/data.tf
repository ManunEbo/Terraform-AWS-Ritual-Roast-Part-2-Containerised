data "aws_vpc" "current" {
  id = var.vpc_id
}

# Fetch the Endpoints Security Group from Layer 1
data "aws_security_group" "rr_endpoints_sg" {
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-vpc-endpoints-sg"]
  }
}