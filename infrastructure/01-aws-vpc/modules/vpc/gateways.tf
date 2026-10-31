# Internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.rr_vpc.id
  tags = merge(var.common_tags, {
    Name = "${var.environment}-igw"
  })
}
