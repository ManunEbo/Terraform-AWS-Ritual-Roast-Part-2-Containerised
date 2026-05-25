output "rr_nat_gateway_k8s" {
    description = "The NAT gateway for the K8s"
    value = aws_nat_gateway.rr_nat_gateway_k8s.id
}