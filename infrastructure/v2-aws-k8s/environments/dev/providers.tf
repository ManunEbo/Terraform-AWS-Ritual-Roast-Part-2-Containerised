terraform {
  required_version = "1.14.3"

  # Remote Backend: This saves the state file to s3 instead of the local disk
  backend "s3" {
    bucket       = "rr-capstone-5b160b287a99a6d9"
    key          = "dev/k8s/state/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }

    # --- ADDED: The Time Provider for IAM consistency ---
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}