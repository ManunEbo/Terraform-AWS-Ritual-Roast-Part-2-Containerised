resource "aws_ecr_repository" "rr_frontend_repo" {
  name                 = "rr-${var.environment}-frontend"
  image_tag_mutability = "IMMUTABLE"

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
  image_tag_mutability = "IMMUTABLE"

  # Allow terraform destroy to wipe the images
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-repo"
  })
}

# Below are simple policies ensures that we only ever keep the 5 most recent images up in the ECR repo,
# automatically purging the older ones and keeping our storage costs flat and predictable.

# --- Frontend Lifecycle Policy ---
resource "aws_ecr_lifecycle_policy" "frontend_lifecycle" {
  repository = aws_ecr_repository.rr_frontend_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --- Backend Lifecycle Policy ---
resource "aws_ecr_lifecycle_policy" "backend_lifecycle" {
  repository = aws_ecr_repository.rr_backend_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}