# Creating the NAT Gateway

# 1. Requesting an Elastic IP (EIP) for the NAT gateway
resource "aws_eip" "rr_nat_gateway_eip_k8s" {
    tags = merge(var.common_tags, {
        Name = "rr-${var.environment}-nat-gateway-eip"
    })
}

# 2. Creating the NAT Gateway
resource "aws_nat_gateway" "rr_nat_gateway_k8s" {
    depends_on = [aws_subnet.rr_k8s_private_subnets]

    # Assign the EIP and the public subnet
    allocation_id = aws_eip.rr_nat_gateway_eip_k8s.id
    subnet_id = var.rr_v1_public_subnet_1_id # <------- must import this subnet id from v1

    tags = merge(var.common_tags, {
        Name = "rr-${var.environment}-nat-gateway-k8s"
    })
}