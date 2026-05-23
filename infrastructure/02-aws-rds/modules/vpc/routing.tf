# Associate the database tier subnets with the private route table
# This is the most sensitive tier.
resource "aws_route_table_association" "database_assoc" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = var.rr_vpc_private_rt_id
}