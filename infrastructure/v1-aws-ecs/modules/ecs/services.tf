#--------------------------------------------------------------
# 1. Frontend ECS Service
#--------------------------------------------------------------

resource "aws_ecs_service" "rr_frontend_service" {
  name            = "rr-${var.environment}-frontend-service"
  cluster         = aws_ecs_cluster.rr_ecs_cluster.id
  task_definition = aws_ecs_task_definition.rr_frontend_task.arn
  desired_count   = 2

  network_configuration {
    subnets         = var.frontend_subnets
    security_groups = [var.frontend_sg_id]

    # The container is in a private subnet and pulls its image securely via VPC Endpoints.
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.frontend_tg_arn
    container_name   = "rr-frontend-container-01"
    container_port   = 3000
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  # TEMPORARILY UNLOCKED: Allowing Terraform to push the new Task Definition
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-service"
  })
}

#--------------------------------------------------------------
# 2. Backend ECS Service
#--------------------------------------------------------------

resource "aws_ecs_service" "rr_backend_service" {
  name            = "rr-${var.environment}-backend-service"
  cluster         = aws_ecs_cluster.rr_ecs_cluster.id
  task_definition = aws_ecs_task_definition.rr_backend_task.arn
  desired_count   = 2

  network_configuration {
    subnets         = var.backend_subnets
    security_groups = [var.backend_sg_id]

    # Secure: Internal service, no public IP
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.backend_tg_arn
    container_name   = "rr-backend-container-01"
    container_port   = 5000
  }

  capacity_provider_strategy {
    # Cost-saving for development!
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  # TEMPORARILY UNLOCKED: Allowing Terraform to push the new Task Definition
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-backend-service"
  })
}