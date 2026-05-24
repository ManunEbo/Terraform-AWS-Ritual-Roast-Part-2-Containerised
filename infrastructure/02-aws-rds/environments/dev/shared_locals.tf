# Retrieving the current account dynamically
data "aws_caller_identity" "current" {}

locals {
  Project        = "ritual-roast-ECS"
  Project_owner  = "Elvy ManunEbo"
  Terraform      = "true"
  Environment    = var.environment
  Region         = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
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

# Retrieving database subnet IDs
locals {
  db_subnet_ids = {
    DataSubnet_2a = data.aws_subnet.DataSubnet_2a.id
    DataSubnet_2b = data.aws_subnet.DataSubnet_2b.id
    DataSubnet_2c = data.aws_subnet.DataSubnet_2c.id
  }
}