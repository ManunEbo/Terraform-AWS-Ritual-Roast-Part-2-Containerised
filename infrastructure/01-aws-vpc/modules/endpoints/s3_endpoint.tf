resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
  policy            = data.aws_iam_policy_document.s3_ecr_layers.json

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-s3-gateway"
  })
}