# =========================================================================
# LAYER 1: Core Networking & Perimeter Foundational Engine
# =========================================================================

# --- 1. The Network Producer ---
module "vpc" {
  source      = "../../modules/vpc"
  common_tags = local.common_tags

  vpc_name    = var.vpc_name
  environment = var.environment
  aws_region  = var.aws_region
  vpc_cidr    = var.vpc_cidr

  public_subnet_list   = var.public_subnet_list
  web_subnet_list      = var.web_subnet_list
  app_subnet_list      = var.app_subnet_list
  database_subnet_list = var.database_subnet_list
  k8s_subnet_list      = var.k8s_subnet_list
}

# --- 2. Shared Security Group Shells ---
module "security_groups" {
  source      = "../../modules/security_groups"
  common_tags = local.common_tags
  aws_region  = var.aws_region

  vpc_id      = module.vpc.vpc_id # Assumes output matches standard syntax
  environment = var.environment
  vpc_name    = var.vpc_name
}

module "alb" {
  source = "../../modules/load_balancers"

  vpc_id = module.vpc.vpc_id
  vpc_name = var.vpc_name
  common_tags = local.common_tags
  environment = var.environment
  public_subnet_ids = module.vpc.public_subnet_ids
  public_alb_sg_id = module.security_groups.alb_sg_id  
}