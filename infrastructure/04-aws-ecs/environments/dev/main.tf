# --- 1. Security groups: Creates the firewalls) ---
module "security_groups" { # <---------- *** Start Here ***
  source      = "../../modules/security_groups"

  common_tags = local.common_tags
  aws_region  = data.aws_region.current.name

  vpc_id      = data.aws_vpc.rr_vpc.id
  environment = var.environment
  vpc_name    = data.aws_vpc.rr_vpc.vpc_name
}

# --- 3. Consumer (LoadBalancers) ---
module "alb" {
  source = "../../modules/load_balancers"

  common_tags        = local.common_tags
  environment        = var.environment
  vpc_id             = data.aws_vpc.rr_vpc.id
  vpc_name           = data.aws_vpc.rr_vpc.vpc_name
  app_subnet_ids     = data.aws_subnets.AppSubnets.ids
  public_alb_sg_id   = data.aws_security_group.public_alb_sg.id
  internal_alb_sg_id = module.security_groups.rr_internal_alb.id
}

# --- 4. Consumer (Endpoints) ---
module "endpoints" {
  source      = "../../modules/endpoints"
  environment = var.environment
  vpc_id      = data.aws_vpc.rr_vpc.id
  vpc_name    = data.aws_vpc.rr_vpc.vpc_name
  aws_region  = data.aws_region.current.name
  common_tags = local.common_tags

  endpoints_sg_id = module.security_groups.rr_endpoints_sg.id
  app_subnet_ids  = data.aws_subnets.AppSubnets.ids
  # Pulling the private route table IDs from the VPC module
  # private_route_table_id = [module.vpc.private_route_table.id]
}

# --- 5. IAM Roles ---
module "iam" {
  source         = "../../modules/iam"

  environment    = var.environment
  common_tags    = local.common_tags
  aws_account_id = local.aws_account_id
  aws_region     = data.aws_region.current.name
  s3_bucket      = local.s3_bucket
}

# --- 6. ECS ---
module "ecs" {
  source      = "../../modules/ecs"
  environment = var.environment
  common_tags = local.common_tags

  # Project metadata for ECR/Logging
  vpc_id         = data.aws_vpc.rr_vpc.id

  # IAM Roles (Centralized module outputs)
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn

  # --- CRITICAL FIX ---
  # Moved the frontend from public_subnets to web_subnets (private) 
  # to match the NAT-less VPC Endpoint architecture!
  frontend_subnets = data.aws_subnets.web_subnets.ids
  backend_subnets  = data.aws_subnets.AppSubnets.ids

  # Security Groups (Firewalls for containers)
  frontend_sg_id = module.security_groups.frontend_sg.id
  backend_sg_id  = module.security_groups.backend_sg.id

  # Load Balancer Integration (Target Group ARNs)
  frontend_tg_arn = data.aws_alb_target_group.frontend_tgt.arn
  backend_tg_arn  = module.alb.backend_tg_arn

  # --- NEW: Environment Variable Injections ---
  # Ensure your alb module has an output named "internal_alb_dns_name"
  internal_alb_dns_name = module.load_balancers.internal_alb_dns_name

  # Note: Replace 'module.rds' with whatever you eventually name your database module block!
  # db_secret_arn = data.aws_secretsmanager_secret.rr_db_secret.arn

  # Delay the creation of containers until the database is ready
  depends_on = [module.rds]
}

# --- 7. Lambda ---
module "lambda" {
  source              = "../../modules/lambda"
  environment         = var.environment
  common_tags         = local.common_tags
  lambda_role_arn     = module.iam.lambda_role_arn
  database_subnet_ids = module.vpc.database_subnets[*].id
  s3_bucket           = local.s3_bucket
  lambda_sg_id        = module.security_groups.lambda_sg.id
}
