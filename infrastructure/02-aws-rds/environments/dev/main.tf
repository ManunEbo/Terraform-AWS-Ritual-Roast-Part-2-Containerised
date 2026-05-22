# --- 1. Consumer (Security groups: Creates the firewalls) ---
module "security_groups" {
  source      = "../../modules/security_groups"
  common_tags = local.common_tags
  aws_region  = var.aws_region

  # This is where we "pull" the data from the VPC module block above
  vpc_id      = module.vpc.vpc.id
  environment = var.environment
  vpc_name    = var.vpc_name
}


# --- 2. IAM Roles ---
module "iam" {
  source         = "../../modules/iam"
  environment    = var.environment
  aws_account_id = local.aws_account_id
  aws_region     = var.aws_region
  vpc_id         = module.vpc.vpc.id
  common_tags    = local.common_tags
  s3_bucket      = local.s3_bucket
}

# --- 3. Lambda ---
module "lambda" {
  source              = "../../modules/lambda"
  environment         = var.environment
  common_tags         = local.common_tags
  lambda_role_arn     = module.iam.lambda_role_arn
  database_subnet_ids = module.vpc.database_subnets[*].id
  s3_bucket           = local.s3_bucket
  lambda_sg_id        = module.security_groups.lambda_sg.id
}

# --- 4. Consumer (Database) ---
module "rds" {
  source = "../../modules/rds"

  environment = var.environment
  common_tags = local.common_tags

  # Pulling networking and security from the VPC and SG modules
  database_subnet_ids = module.vpc.database_subnets[*].id
  database_sg_id      = module.security_groups.database_sg.id

  # Credentials passed in from your terminal or secrets file at deploy time
  db_username = var.db_username
  db_password = var.db_password

  # The Lambda rotation function ARN exported from the lambda module
  rotation_lambda_arn = module.lambda.lambda_function_arn
}