output "endpoints_sg_id" {
  description = "The SG ID attached to the VPC Endpoints"
  value       = var.endpoints_sg_id
}

output "endpoint_ids" {
  description = "The IDs of the created VPC Endpoints"
  value = {
    # secrets = aws_vpc_endpoint.secretsmanager.id
    ecr_api = aws_vpc_endpoint.ecr_api.id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr.id
    logs    = aws_vpc_endpoint.logs.id
    s3      = aws_vpc_endpoint.s3.id
  }
}