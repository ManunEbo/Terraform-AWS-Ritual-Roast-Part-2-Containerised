module "ecr" {
  source      = "../../modules/ecr"
  environment = var.environment
  common_tags = local.common_tags
}

module "iam" {
  source            = "../../modules/iam"
  environment       = var.environment
  oidc_provider_arn = module.tls.oidc_provider_arn
  frontend_repo_arn = module.ecr.frontend_repo_arn
  backend_repo_arn  = module.ecr.backend_repo_arn
}

module "tls" {
  source = "../../modules/tls"
}