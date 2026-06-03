# ==========================================
# MODULES: The V2 K3s Infrastructure
# ==========================================

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

  # --- NEW: Passing the Sensitive Tokens ---
  github_pat    = var.github_pat
  grafana_token = var.grafana_token  
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
  k8s_private_subnets = data.aws_subnets.rr_k8s_subnets.ids
  
  # 1. Control Plane Wiring (HA Datastore Access)
  control_plane_sg_id       = module.security_k8s.control_plane_sg_id
  iam_profile_control_plane = module.iam_k8s.control_plane_profile_name

  # 2. Frontend Worker Wiring (DMZ / ALB Access)
  worker_frontend_sg_id       = module.security_k8s.worker_frontend_sg_id
  iam_profile_worker_frontend = module.iam_k8s.worker_frontend_profile_name
  
  # 3. Backend Worker Wiring (Secure Tier / DB Access)
  worker_backend_sg_id        = module.security_k8s.worker_backend_sg_id
  iam_profile_worker_backend  = module.iam_k8s.worker_backend_profile_name

  control_plane_type = var.control_plane_type
  worker_node_type   = var.worker_node_type
  common_tags        = local.common_tags
}