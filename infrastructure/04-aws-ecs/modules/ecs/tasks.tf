#--------------------------------------------------------------
# 1. CloudWatch Log Groups
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "rr_frontend_logs" {
  name              = "/ecs/rr-${var.environment}-frontend"
  retention_in_days = 7
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-logs"
  })
}

resource "aws_cloudwatch_log_group" "rr_backend_logs" {
  name              = "/ecs/rr-${var.environment}-backend"
  retention_in_days = 7

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-logs"
  })
}

#--------------------------------------------------------------
# 2. Frontend Task Definition (The RR Web Blueprint)
#--------------------------------------------------------------
resource "aws_ecs_task_definition" "rr_frontend_task" {
  family                   = "rr-${var.environment}-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "rr-frontend-container-01"
      image     = "${data.aws_Caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/rr-${var.environment}-frontend:latest"
      essential = true

      # OS Unlocked: Using Fargate's native 20GB ephemeral storage
      readonlyRootFilesystem = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      # --- MAJOR ARCHITECTURAL UPGRADE ---
      # Injecting specific environment variables to securely bridge the network tier.
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
          "awslogs-region"        = data.aws_region.name
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
# 3. Backend Task Definition (The RR API Blueprint)
#--------------------------------------------------------------
resource "aws_ecs_task_definition" "rr_backend_task" {
  family                   = "rr-${var.environment}-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "rr-backend-container-01"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/rr-${var.environment}-backend:latest"
      essential = true

      # OS Unlocked: Allowing Gunicorn to write heartbeat files to /tmp securely
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
          value = data.aws_region.current.name
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rr_backend_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-task"
  })
}