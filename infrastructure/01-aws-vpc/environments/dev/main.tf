# --- 1. The Producer (Creates the Network) ---
module "vpc" {
  source      = "../../modules/vpc" # Adjusted path to reach modules from environments/dev/
  common_tags = local.common_tags

  # Project Metadata
  vpc_name    = var.vpc_name
  environment = var.environment
  aws_region  = var.aws_region

  # Networking CIDR
  vpc_cidr = var.vpc_cidr

  # Passing the Lists of Objects (The subnets)
  public_subnet_list   = var.public_subnet_list
  web_subnet_list      = var.web_subnet_list
  app_subnet_list      = var.app_subnet_list
  database_subnet_list = var.database_subnet_list
  k8s_subnet_list = var.k8s_subnet_list
}

# --- 2. Consumer (Security groups: Creates the firewalls) ---
module "security_groups" {
  source      = "../../modules/security_groups"
  common_tags = local.common_tags
  aws_region  = var.aws_region

  # This is where we "pull" the data from the VPC module block above
  vpc_id      = module.vpc.vpc.id
  environment = var.environment
  vpc_name    = var.vpc_name
}

# --- 3. Consumer (LoadBalancers) ---
module "alb" {
  source = "../../modules/load_balancers"

  vpc_id             = module.vpc.vpc.id
  vpc_name           = var.vpc_name
  common_tags        = local.common_tags
  environment        = var.environment
  public_subnet_ids  = module.vpc.public_subnets[*].id
  app_subnet_ids     = module.vpc.app_subnets[*].id
  public_alb_sg_id   = module.security_groups.alb_sg.id
  internal_alb_sg_id = module.security_groups.internal_alb_sg.id
}

# --- 4. Consumer (Endpoints) ---
module "endpoints" {
  source      = "../../modules/endpoints"
  environment = var.environment
  vpc_id      = module.vpc.vpc.id
  vpc_name    = var.vpc_name
  aws_region  = var.aws_region
  common_tags = local.common_tags

  endpoints_sg_id = module.security_groups.endpoints_sg.id
  app_subnet_ids  = module.vpc.app_subnets[*].id
  # Pulling the private route table IDs from the VPC module
  # private_route_table_id = [module.vpc.private_route_table.id]
}

# --- 5. IAM Roles ---
module "iam" {
  source         = "../../modules/iam"
  environment    = var.environment
  aws_account_id = local.aws_account_id
  aws_region     = var.aws_region
  vpc_id         = module.vpc.vpc.id
  common_tags    = local.common_tags
  s3_bucket      = local.s3_bucket
}

# --- 6. ECS ---
module "ecs" {
  source      = "../../modules/ecs"
  environment = var.environment
  common_tags = local.common_tags

  # Project metadata for ECR/Logging
  aws_region     = var.aws_region
  aws_account_id = local.aws_account_id
  vpc_id         = module.vpc.vpc.id

  # IAM Roles (Centralized module outputs)
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn

  # --- CRITICAL FIX ---
  # Moved the frontend from public_subnets to web_subnets (private) 
  # to match the NAT-less VPC Endpoint architecture!
  frontend_subnets = module.vpc.web_subnets[*].id
  backend_subnets  = module.vpc.app_subnets[*].id

  # Security Groups (Firewalls for containers)
  frontend_sg_id = module.security_groups.frontend_sg.id
  backend_sg_id  = module.security_groups.backend_sg.id

  # Load Balancer Integration (Target Group ARNs)
  frontend_tg_arn = module.alb.frontend_tg_arn
  backend_tg_arn  = module.alb.backend_tg_arn

  # --- NEW: Environment Variable Injections ---
  # Ensure your alb module has an output named "internal_alb_dns_name"
  internal_alb_dns_name = module.alb.internal_alb_dns_name

  # Note: Replace 'module.rds' with whatever you eventually name your database module block!
  db_secret_arn = module.rds.db_secret_arn

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

