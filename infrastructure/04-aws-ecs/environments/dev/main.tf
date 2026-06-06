# --- 1. Compute Security Groups (Migrated from Layer 1) ---
module "security_groups" {
  source      = "../../modules/security_groups"
  common_tags = local.common_tags
  vpc_id      = data.aws_vpc.rr_vpc.id
  environment = var.environment

  # Satisfying the module's strict variables
  vpc_name    = data.aws_vpc.rr_vpc.tags["Name"]
  aws_region  = data.aws_region.current.id
}

# --- 2. Load Balancers (Public & Internal) ---
module "alb" {
  # Ensure this spelling matches your folder exactly (hyphen vs underscore)
  source = "../../modules/load-balancers" 

  environment = var.environment
  common_tags = local.common_tags

  # VPC Info
  vpc_id   = data.aws_vpc.rr_vpc.id
  vpc_name = data.aws_vpc.rr_vpc.tags["Name"] # The valid way to extract the name dynamically

  # Subnets
  app_subnet_ids    = data.aws_subnets.AppSubnets.ids
  public_subnet_ids = data.aws_subnets.public_subnets.ids

  # Security Groups
  public_alb_sg_id   = data.aws_security_group.public_alb_sg.id
  
  # Note: Ensure "rr_internal_alb" matches the exact output name in your security_groups module
  internal_alb_sg_id = module.security_groups.internal_alb_sg.id

  # The new wiring connection to the public ALB
  gateway_listener_arn = data.aws_lb_listener.gateway_http_listener.arn
}

# --- 3. Compute IAM Roles ---
module "iam" {
  source         = "../../modules/iam"

  environment    = var.environment
  common_tags    = local.common_tags
  aws_account_id = local.aws_account_id
  aws_region     = data.aws_region.current.id
  s3_bucket      = local.s3_bucket
}

# --- 4. Elastic Container Service ---
module "ecs" {
  source      = "../../modules/ecs"
  
  environment = var.environment
  common_tags = local.common_tags

  # Network
  vpc_id           = data.aws_vpc.rr_vpc.id
  frontend_subnets = data.aws_subnets.web_subnets.ids
  backend_subnets  = data.aws_subnets.AppSubnets.ids

  # IAM Roles (ZERO-TRUST SPLIT)
  ecs_execution_role_arn     = module.iam.ecs_execution_role_arn
  ecs_frontend_task_role_arn = module.iam.ecs_frontend_task_role_arn
  ecs_backend_task_role_arn  = module.iam.ecs_backend_task_role_arn

  # Security Groups
  frontend_sg_id = module.security_groups.frontend_sg.id
  backend_sg_id  = module.security_groups.backend_sg.id

  # Routing (Public ALB comes from data.tf, Internal comes from module)
  frontend_tg_arn       = module.alb.frontend_tg_arn
  backend_tg_arn        = module.alb.backend_tg_arn
  internal_alb_dns_name = module.alb.internal_alb_dns_name
}

module "endpoints" {
  source          = "../../modules/endpoints"
  
  vpc_id          = data.aws_vpc.rr_vpc.id
  vpc_name        = data.aws_vpc.rr_vpc.tags["Name"]
  aws_region      = data.aws_region.current.id
  environment     = var.environment
  common_tags     = local.common_tags
  
  endpoints_sg_id = data.aws_security_group.rr_endpoints_sg.id
  app_subnet_ids  = data.aws_subnets.AppSubnets.ids
  route_table_ids = data.aws_route_tables.private_rts.ids
  app_s3_bucket   = local.s3_bucket 
  
  # Injecting specific identities for the Zero-Trust S3 policy
  ecs_execution_role_arn     = module.iam.ecs_execution_role_arn
  ecs_backend_task_role_arn  = module.iam.ecs_backend_task_role_arn
  ecs_frontend_task_role_arn = module.iam.ecs_frontend_task_role_arn
}