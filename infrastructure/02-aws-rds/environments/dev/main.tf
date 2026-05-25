# --- 1. Consumer (Security groups: Creates the firewalls) ---
module "security_groups" {
  source      = "../../modules/security_groups"
  common_tags = local.common_tags
  aws_region  = data.aws_caller_identity.current.aws_region # <---  verify that this is the most efficient code for this task

  # This is where we "pull" the data from the VPC module block above
  vpc_id      = data.aws_vpc.rr_v1_vpc.id
  environment = var.environment
  vpc_name    = data.aws_vpc.rr_v1_vpc.vpc_name
}


# --- 2. IAM Roles ---
module "iam" {
  source         = "../../modules/iam"
  environment    = var.environment
  vpc_id         = data.aws_vpc.rr_v1_vpc.id
  common_tags    = local.common_tags
}

# --- 3. Lambda ---
module "lambda" {
  source              = "../../modules/lambda"
  environment         = var.environment
  common_tags         = local.common_tags
  lambda_role_arn     = module.iam.lambda_role_arn
  database_subnet_ids = data.aws_subnets.rr_db_subnets.ids
  lambda_sg_id        = module.security_groups.lambda_sg.id
}

# --- 4. Consumer (Database) ---
module "rds" {
  source = "../../modules/rds"

  environment = var.environment
  common_tags = local.common_tags

  # Pulling networking and security from the VPC and SG modules
  database_subnet_ids = data.aws_subnets.rr_db_subnets.ids
  database_sg_id      = module.security_groups.database_sg.id

  # Credentials passed in from your terminal or secrets file at deploy time
  db_username = var.db_username
  db_password = var.db_password

  # The Lambda rotation function ARN exported from the lambda module
  rotation_lambda_arn = module.lambda.lambda_function_arn
}
