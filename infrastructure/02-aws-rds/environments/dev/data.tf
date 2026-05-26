# ==========================================
# DATA SOURCES: Fetching the Layer 1 Foundation
# ==========================================
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "rr_vpc" {
  tags = local.common_tags_vpc
  filter {
    name   = "tag:Name"
    values = ["rr-${var.environment}-*"]
  }
}

data "aws_subnets" "rr_db_subnets" {
  tags = local.common_tags_vpc
  filter {
    name   = "tag:Name"
    values = ["DataSubnet-*"]
  }
}