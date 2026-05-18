resource "aws_ecr_repository" "rr_frontend_repo" {
  name                 = "rr-${var.environment}-frontend"
  image_tag_mutability = "MUTABLE"

  # Allow terraform destroy to wipe the images
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-repo"
  })
}

resource "aws_ecr_repository" "rr_backend_repo" {
  name                 = "rr-${var.environment}-backend"
  image_tag_mutability = "MUTABLE"

  # Allow terraform destroy to wipe the images
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-repo"
  })
}