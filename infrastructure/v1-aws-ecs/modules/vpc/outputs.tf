#--- VPC Object ---
# This gives access to .id, .cidr_block, .main_route_table_id, etc.
output "vpc" {
  description = "The entire VPC resource object"
  value       = aws_vpc.rr_vpc
}

# --- Subnet Objects (Lists of Objects) ---
# Because we used 'count', these return a list of the full resource objects.
output "public_subnets" {
  description = "List of all public subnet objects"
  value       = aws_subnet.public
}

output "web_subnets" {
  description = "List of all web tier subnet objects"
  value       = aws_subnet.web
}

output "app_subnets" {
  description = "List of all app tier subnet objects"
  value       = aws_subnet.app
}

output "database_subnets" {
  description = "List of all database tier subnet objects"
  value       = aws_subnet.database
}

# --- Gateway & Routing Objects ---
output "internet_gateway" {
  description = "The Internet Gateway object"
  value       = aws_internet_gateway.main
}

output "private_route_table" {
  description = "The private route table object"
  value       = aws_route_table.private
}