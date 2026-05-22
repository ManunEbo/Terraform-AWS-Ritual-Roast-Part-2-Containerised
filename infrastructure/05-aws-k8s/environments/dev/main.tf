# ==========================================
# MODULES: The V2 K3s Infrastructure
# ==========================================

module "vpc_k8s" {
  source = "../../modules/vpc_k8s"

  environment              = var.environment
  vpc_id                   = data.aws_vpc.rr_v1_vpc.id
  rr_v1_igw                = data.aws_internet_gateway.rr_v1_igw.id
  rr_v1_public_subnet_1_id = data.aws_subnet.rr_v1_public_subnet_1.id
  common_tags              = local.common_tags
  
  # Pass the list variable we just created in dev/terraform.tfvars
  k8s_subnet_list          = var.k8s_subnet_list
}

module "security_k8s" {
  source = "../../modules/security_k8s"

  environment = var.environment
  vpc_id      = data.aws_vpc.rr_v1_vpc.id
  rds_sg_id   = data.aws_security_group.rr_v1_rds_sg.id
  common_tags = local.common_tags
  
  # Passing the V1 workload SGs  for zero-trust Istio ingress
  alb_sg_id =  data.aws_security_group.rr_v1_alb_sg.id
  web_sg_id = data.aws_security_group.rr_v1_web_sg.id
  app_sg_id = data.aws_security_group.rr_v1_app_sg.id
}

module "iam_k8s" {
  source = "../../modules/iam_k8s"

  environment = var.environment
  common_tags = local.common_tags
}

module "compute_k8s" {
  source = "../../modules/compute_k8s"

  environment = var.environment
  vpc_id      = data.aws_vpc.rr_v1_vpc.id
  subnet_ids  = module.vpc_k8s.private_subnet_ids
  
  control_plane_sg_id   = module.security_k8s.control_plane_sg_id
  worker_node_sg_id     = module.security_k8s.worker_node_sg_id
  instance_profile_name = module.iam_k8s.k3s_instance_profile_name

  control_plane_type = var.control_plane_type
  worker_node_type   = var.worker_node_type
  common_tags        = local.common_tags
}