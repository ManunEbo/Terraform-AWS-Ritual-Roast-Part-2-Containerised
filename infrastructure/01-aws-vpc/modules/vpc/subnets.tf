resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_list)
  vpc_id                  = aws_vpc.rr_vpc.id
  cidr_block              = var.public_subnet_list[count.index].cidr
  availability_zone       = var.public_subnet_list[count.index].az
  map_public_ip_on_launch = true
  tags = merge(var.common_tags, {
    Name = var.public_subnet_list[count.index].subnet_name
  })
}

resource "aws_subnet" "web" {
  count             = length(var.web_subnet_list)
  vpc_id            = aws_vpc.rr_vpc.id
  cidr_block        = var.web_subnet_list[count.index].cidr
  availability_zone = var.web_subnet_list[count.index].az
  tags = merge(var.common_tags, {
    Name = var.web_subnet_list[count.index].subnet_name
  })
}


resource "aws_subnet" "app" {
  count             = length(var.app_subnet_list)
  vpc_id            = aws_vpc.rr_vpc.id
  cidr_block        = var.app_subnet_list[count.index].cidr
  availability_zone = var.app_subnet_list[count.index].az
  tags = merge(var.common_tags, {
    Name = var.app_subnet_list[count.index].subnet_name
  })
}

resource "aws_subnet" "database" {
  count             = length(var.database_subnet_list)
  vpc_id            = aws_vpc.rr_vpc.id
  cidr_block        = var.database_subnet_list[count.index].cidr
  availability_zone = var.database_subnet_list[count.index].az
  tags = merge(var.common_tags, {
    Name = var.database_subnet_list[count.index].subnet_name
  })
}

# 1. Create the K8s Private Subnets
# Creating the database subnets
# For the subnets only, we're ditching the ${var.environment} to be consistent with the v1 subnets
resource "aws_subnet" "k8s" {
    count             = length(var.k8s_subnet_list)
    vpc_id            = aws_vpc.rr_vpc.id
    cidr_block        = var.k8s_subnet_list[count.index].cidr
    availability_zone = var.k8s_subnet_list[count.index].az

    # The kubernetes.io/role/internal-elb tag is a strict K8s requirement.
    # It allows the AWS Cloud Controller to automatically find these subnets 
    # when you create internal LoadBalancers in Kubernetes later.
    tags = merge(var.common_tags, {
        Name = var.k8s_subnet_list[count.index].subnet_name
        "kubernetes.io/role/internal-elb" = "1"
    })
}