# --- 1. Core VPC Identifier ---
output "vpc_id" {
  description = "The ID of the provisioned primary VPC"
  value       = aws_vpc.rr_vpc.id
}

output "vpc_cidr_block" {
  description = "The network CIDR range allocated to the VPC"
  value       = aws_vpc.rr_vpc.cidr_block
}

# --- 2. Subnet ID Arrays ---
output "public_subnet_ids" {
  description = "IDs of the public edge subnets"
  value       = aws_subnet.public[*].id
}

output "web_subnet_ids" {
  description = "IDs of the isolated web tier subnets"
  value       = aws_subnet.web[*].id
}

output "app_subnet_ids" {
  description = "IDs of the isolated application tier subnets"
  value       = aws_subnet.app[*].id
}

output "database_subnet_ids" {
  description = "IDs of the strictly private persistence subnets"
  value       = aws_subnet.database[*].id
}

output "k8s_subnet_ids" {
  description = "IDs of the dedicated service mesh computing subnets"
  value       = aws_subnet.k8s[*].id
}

# --- 3. Gateway References ---
output "internet_gateway_id" {
  description = "The Core Internet Gateway identifier"
  value       = aws_internet_gateway.main.id
}

output "private_route_table_id" {
  description = "Identifier for the standalone private internal route table"
  value       = aws_route_table.private.id
}

output "k8s_route_table_id" {
  description = "Identifier for the standalone service mesh route table"
  value       = aws_route_table.k8s_rt.id
}