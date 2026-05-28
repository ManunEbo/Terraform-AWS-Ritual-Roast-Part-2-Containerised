resource "aws_vpc" "rr_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-${var.vpc_name}"
  })
}