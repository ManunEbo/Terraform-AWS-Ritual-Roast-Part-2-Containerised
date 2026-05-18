#--------------------------------------------------------------
# Ritual Roast - ECS Cluster
#--------------------------------------------------------------
resource "aws_ecs_cluster" "rr_ecs_cluster" {
  name = "rr-${var.environment}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-ecs-cluster"
  })
}

# Capacity providers: Fargate & Fargate_spot
resource "aws_ecs_cluster_capacity_providers" "rr_ecs_cp" {
  cluster_name = aws_ecs_cluster.rr_ecs_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}