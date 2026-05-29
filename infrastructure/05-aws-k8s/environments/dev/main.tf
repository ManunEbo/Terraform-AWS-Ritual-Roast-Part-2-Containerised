# ==========================================
# MODULES: The V2 K3s Infrastructure
# ==========================================

module "vpc_k8s" {
  source = "../../modules/vpc_k8s"

  environment           = var.environment
  vpc_id                = data.aws_vpc.rr_vpc.id
  rr_igw                = data.aws_internet_gateway.rr_igw
  rr_public_subnet_1_id = data.aws_subnet.rr_public_subnet_1.id
  rr_k8s_subnets_ids    = data.aws_subnets.rr_k8s_subnets.ids
  common_tags           = local.common_tags
  rr_k8s_private_rt_id  = data.aws_route_table.rr_k8s_private_rt.id
}

module "security_k8s" {
  source = "../../modules/security_k8s"

  environment = var.environment
  vpc_id      = data.aws_vpc.rr_vpc.id
  rds_sg_id   = data.aws_security_group.rr_rds_sg.id
  common_tags = local.common_tags
  
  # Passing the V1 workload SGs for zero-trust Istio ingress
  alb_sg_id = data.aws_security_group.rr_alb_sg.id
  web_sg_id = data.aws_security_group.rr_web_sg.id
  app_sg_id = data.aws_security_group.rr_app_sg.id
}

module "iam_k8s" {
  source = "../../modules/iam_k8s"
  
  aws_region  = var.aws_region
  environment = var.environment
  common_tags = local.common_tags
}

module "compute_k8s" {
  source = "../../modules/compute_k8s"

  environment = var.environment
  aws_region  = var.aws_region
  vpc_id      = data.aws_vpc.rr_vpc.id
  
  # Synchronized Compute Variables ---
  k8s_private_subnets = module.vpc_k8s.private_subnet_ids
  
  control_plane_sg_id = module.security_k8s.control_plane_sg_id
  worker_sg_id        = module.security_k8s.worker_node_sg_id
  
  # Split IAM profiles for Zero-Trust token retrieval
  iam_profile_control_plane = module.iam_k8s.k3s_control_plane_profile_name
  iam_profile_worker        = module.iam_k8s.k3s_worker_profile_name
  control_plane_type = var.control_plane_type
  worker_node_type   = var.worker_node_type
  common_tags        = local.common_tags
}