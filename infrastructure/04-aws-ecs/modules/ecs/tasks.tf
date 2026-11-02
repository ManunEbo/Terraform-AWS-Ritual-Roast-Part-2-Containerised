#--------------------------------------------------------------
# 0. Image lookups: deploy by digest, not by the "latest" tag
#--------------------------------------------------------------
# Finds the most recently pushed image in each ECR repository and returns its
# digest (sha256:...), the image's unique content fingerprint. A digest can
# never point at different content, so each new image produces a new task
# definition revision, which ECS then rolls out.
# If a repository is empty, the plan fails here: push the images (Layer 3
# pipeline) before applying this layer.

data "aws_ecr_image" "frontend" {
  repository_name = "rr-${var.environment}-frontend"
  most_recent     = true
}

data "aws_ecr_image" "backend" {
  repository_name = "rr-${var.environment}-backend"
  most_recent     = true
}

#--------------------------------------------------------------
# 1. Frontend Task Definition (The RR Web Greenprint)
#--------------------------------------------------------------

resource "aws_ecs_task_definition" "rr_frontend_task" {
  family                   = "rr-${var.environment}-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512  # Upgraded compute
  memory                   = 1024 # Upgraded compute
  execution_role_arn       = var.ecs_execution_role_arn

  # ZERO-TRUST FIX: Frontend gets its own isolated role (No DB Secret Access)
  task_role_arn = var.ecs_frontend_task_role_arn

  # 1. Carve out a block of Fargate's ephemeral storage
  volume {
    name = "nextjs-cache"
  }

  container_definitions = jsonencode([
    {
      name = "rr-frontend-container-01"

      # Pulling securely from ECR via VPC Endpoints, pinned to an exact image digest
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com/rr-${var.environment}-frontend@${data.aws_ecr_image.frontend.image_digest}"
      essential = true

      # The OS remains mathematically locked
      readonlyRootFilesystem = true

      # 2. Mount the empty volume exclusively to the cache path
      mountPoints = [
        {
          sourceVolume  = "nextjs-cache"
          containerPath = "/app/.next/cache"
          readOnly      = false
        }
      ]

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "BACKEND_URL"
          value = "http://${var.internal_alb_dns_name}"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rr_frontend_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-task"
  })
}

#--------------------------------------------------------------
# 2. Backend Task Definition (The RR API Greenprint)
#--------------------------------------------------------------
resource "aws_ecs_task_definition" "rr_backend_task" {
  family                   = "rr-${var.environment}-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_execution_role_arn

  # ZERO-TRUST FIX: Backend gets its own isolated role (Has DB Secret Access)
  task_role_arn = var.ecs_backend_task_role_arn

  container_definitions = jsonencode([
    {
      name = "rr-backend-container-01"
      # Pinned to an exact image digest
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com/rr-${var.environment}-backend@${data.aws_ecr_image.backend.image_digest}"
      essential = true

      # Locking the root file system
      readonlyRootFilesystem = true

      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]

      # --- MAJOR ARCHITECTURAL UPGRADE ---
      # Injecting specific environment variables to securely bridge the data tier.
      environment = [
        {
          name  = "SECRET_ARN"
          value = data.aws_secretsmanager_secret.rr_db_secret.arn
        },
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.id
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rr_backend_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-task"
  })
}