#------------------------------------------------------
# Public route table
#------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.rr_vpc.id
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-${var.vpc_name}-public-rt"
  })
}

# Standalone route resource for the public route table
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

#------------------------------------------------------
# Private route table (No Direct Internet Access)
#------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.rr_vpc.id
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-${var.vpc_name}-private-rt"
  })
}

# Associate public subnets to the public route table
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

# Associate the Web tier with the private route table
resource "aws_route_table_association" "web_assoc" {
  count          = length(aws_subnet.web)
  subnet_id      = aws_subnet.web[count.index].id
  route_table_id = aws_route_table.private.id
}

# Associate the database tier subnets with the private route table
resource "aws_route_table_association" "database_assoc" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------
# K8s Route table
#------------------------------------------------------

# 1. Create a dedicated Route Table for K8s
resource "aws_route_table" "k8s_rt" {
  vpc_id = aws_vpc.rr_vpc.id

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-${var.vpc_name}-k8s-private-rt"
  })
}

# Associate the K8s tier subnets with the k8s_rt route table
resource "aws_route_table_association" "k8s_assoc" {
  count          = length(aws_subnet.k8s)
  subnet_id      = aws_subnet.k8s[count.index].id
  route_table_id = aws_route_table.k8s_rt.id
}