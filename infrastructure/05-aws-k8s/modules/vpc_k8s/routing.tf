# 2. Route outbound traffic to the V1 NAT Gateway
resource "aws_route" "rr_k8s_nat_route" {
    route_table_id = aws_route_table.rr_k8s_private_rt.id
    destination_cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.rr_nat_gateway_k8s.id
}

# 3. Associate the new subnets with the K8s Route Table
resource "aws_route_table_association" "rr_k8s_private_rta" {
    count = length(aws_subnet.rr_k8s_private_subnets)
    subnet_id = aws_subnet.rr_k8s_private_subnets[count.index].id
    route_table_id = aws_route_table.rr_k8s_private_rt.id

}