locals {
  Project        = "ritual-roast-ECS"
  Project_owner  = "Elvy ManunEbo"
  Terraform      = "true"
  Environment    = var.environment
  Region         = data.aws_region.current.id
  aws_account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Project       = local.Project
    Project_owner = local.Project_owner
    Terraform     = local.Terraform
    Environment   = local.Environment
    Region        = local.Region
  }

  common_tags_vpc = {
    Project       = local.Project
    Project_owner = local.Project_owner
    Terraform     = local.Terraform
    Environment   = local.Environment
    Region        = local.Region
  }
}