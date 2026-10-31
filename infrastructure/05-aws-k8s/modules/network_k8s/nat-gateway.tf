# 1. Allocate a static Public IP for the NAT Gateway
resource "aws_eip" "rr_k8s_nat_eip" {
  domain = "vpc"
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-nat-eip"
  })
}

# 2. Creating the NAT Gateway dynamically in Layer 5
resource "aws_nat_gateway" "rr_k8s_nat" {
  allocation_id = aws_eip.rr_k8s_nat_eip.id
  subnet_id     = var.public_subnet_id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-nat-gw"
  })
}

# 3. INJECTED ROUTE: Wire the Layer 1 Route Table to the Layer 5 NAT
resource "aws_route" "rr_inject_k8s_internet_access" {
  route_table_id         = data.aws_route_table.k8s_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.rr_k8s_nat.id
}