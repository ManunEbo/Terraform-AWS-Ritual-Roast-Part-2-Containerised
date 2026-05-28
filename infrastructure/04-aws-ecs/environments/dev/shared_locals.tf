# Retrieving the current account dynamically
data "aws_caller_identity" "current" {}

locals {
  Project        = "ritual-roast-ECS"
  Project_owner  = "Elvy ManunEbo"
  Terraform      = "true"
  Environment    = var.environment
  Region         = data.aws_region.current.id
  aws_account_id = data.aws_caller_identity.current.account_id
  s3_bucket      = "rr-capstone-5b160b287a99a6d9"
}

locals {
  common_tags = {
    Project       = local.Project
    Project_owner = local.Project_owner
    Terraform     = local.Terraform
    Environment   = local.Environment
    Region        = local.Region
  }
}