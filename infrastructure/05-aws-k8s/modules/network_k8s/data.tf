# 1. Find the K8s Private Route Table from Layer 1
data "aws_route_table" "k8s_rt" {
  vpc_id = var.vpc_id

  filter {
    name = "tag:Name"
    # Using the exact name defined in your Layer 1 routing.tf
    values = ["rr-${var.environment}-${var.vpc_name}-k8s-private-rt"]
  }
}