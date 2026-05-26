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

# --- 3. Shared Ingress Load Balancers ---
module "alb" {
  source = "../../modules/load_balancers"

  vpc_id             = module.vpc.vpc_id
  vpc_name           = var.vpc_name
  common_tags        = local.common_tags
  environment        = var.environment
  public_subnet_ids  = module.vpc.public_subnet_ids
  app_subnet_ids     = module.vpc.app_subnet_ids
  public_alb_sg_id   = module.security_groups.alb_sg_id
  internal_alb_sg_id = module.security_groups.internal_alb_sg_id
}

# --- 4. Core Private VPC Endpoints ---
module "endpoints" {
  source      = "../../modules/endpoints"
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  vpc_name    = var.vpc_name
  aws_region  = var.aws_region
  common_tags = local.common_tags

  endpoints_sg_id = module.security_groups.endpoints_sg_id
  app_subnet_ids  = module.vpc.app_subnet_ids
}

# --- 5. Shared Core Operational IAM Structural Roles ---
module "iam" {
  source         = "../../modules/iam"
  environment    = var.environment
  aws_account_id = local.aws_account_id
  aws_region     = var.aws_region
  vpc_id         = module.vpc.vpc_id
  common_tags    = local.common_tags
  s3_bucket      = local.s3_bucket
}