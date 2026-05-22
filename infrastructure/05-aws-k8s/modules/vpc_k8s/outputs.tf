output "private_subnet_ids" {
  description = "The IDs of the K8s private subnets"
  value       = aws_subnet.rr_k8s_private_subnets[*].id
}

output "rr_nat_gateway_k8s" {
    description = "The NAT gateway for the K8s"
    value = aws_nat_gateway.rr_nat_gateway_k8s.id
}