# 2. Route outbound traffic to the V1 NAT Gateway
resource "aws_route" "rr_k8s_nat_route" {
    route_table_id = var.rr_k8s_private_rt_id
    destination_cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.rr_nat_gateway_k8s.id
}

# 3. Associate the new subnets with the K8s Route Table
resource "aws_route_table_association" "rr_k8s_private_rta" {
    count = length(var.rr_k8s_subnets_ids)
    subnet_id = var.rr_k8s_subnets_ids[count.index]
    route_table_id = var.rr_k8s_private_rt_id
}