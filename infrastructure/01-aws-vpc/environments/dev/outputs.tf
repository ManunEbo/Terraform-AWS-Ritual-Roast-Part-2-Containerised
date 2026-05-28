output "vpc_id" {
  description = "The core VPC identifier"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of public subnet identifiers"
  value       = module.vpc.public_subnet_ids
}

output "k8s_subnet_ids" {
  description = "List of dedicated K8s subnet identifiers allocated for service mesh nodes"
  value       = module.vpc.k8s_subnet_ids
}

output "database_subnet_ids" {
  description = "List of isolated database subnets for RDS placement"
  value       = module.vpc.database_subnet_ids
}

output "public_alb_sg_id" {
  description = "The public load balancer boundary security identity"
  value       = module.security_groups.alb_sg_id
}