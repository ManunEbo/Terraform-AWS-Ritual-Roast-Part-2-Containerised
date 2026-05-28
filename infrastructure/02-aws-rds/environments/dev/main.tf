# --- 1. Layer 2 Security Group Shells ---
module "security_groups" {
  source      = "../../modules/security_groups"
  common_tags = local.common_tags
  
  aws_region  = data.aws_region.current.id 
  vpc_id      = data.aws_vpc.rr_vpc.id
  environment = var.environment
  vpc_name    = var.vpc_name 
}

# --- 2. IAM Roles ---
module "iam" {
  source         = "../../modules/iam"
  environment    = var.environment
  common_tags    = local.common_tags
}

# --- 3. Lambda Rotation Engine ---
module "lambda" {
  source              = "../../modules/lambda"
  environment         = var.environment
  common_tags         = local.common_tags
  lambda_role_arn     = module.iam.lambda_role_arn
  database_subnet_ids = data.aws_subnets.rr_db_subnets.ids
  lambda_sg_id        = module.security_groups.lambda_sg.id
}

# --- 4. Database Engine ---
module "rds" {
  source = "../../modules/rds"

  environment = var.environment
  common_tags = local.common_tags

  database_subnet_ids = data.aws_subnets.rr_db_subnets.ids
  database_sg_id      = module.security_groups.database_sg.id

  db_username = var.db_username
  db_password = var.db_password
  
  rotation_lambda_arn = module.lambda.lambda_function_arn
}