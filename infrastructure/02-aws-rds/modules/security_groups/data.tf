# Fetch the Endpoints Security Group from Layer 1
data "aws_security_group" "rr_endpoints_sg" {
  vpc_id = var.vpc_id
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-vpc-endpoints-sg"]
  }
}