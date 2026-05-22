# Public route
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.rr_vpc.id
  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-public-rt"
  })
}

# Stand alone route resource for the public route table
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Private route table (No Internet Access)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.rr_vpc.id
  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-rt"
  })
}

# Associate public subnets to the public route
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate the App subnets to the private route table
resource "aws_route_table_association" "app_assoc" {
  count          = length(aws_subnet.app)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

# Asssotiate the Web tier with the private subnet
# Note even though these handle "Web" traffic, they sit behind the ALB
# and don't need a direct route to the IGW.
resource "aws_route_table_association" "web_assoc" {
  count          = length(aws_subnet.web)
  subnet_id      = aws_subnet.web[count.index].id
  route_table_id = aws_route_table.private.id
}

# Associate the database tier subnets with the private route table
# This is the most sensitive tier.
resource "aws_route_table_association" "database_assoc" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private.id
}