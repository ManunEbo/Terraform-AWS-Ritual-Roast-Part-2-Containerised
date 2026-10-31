#--- Target Group for Frontend ECS Containers ---
resource "aws_lb_target_group" "rr_frontend" {
  name        = "rr-${var.environment}-ecs-frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/api/health"
    port                = "3000"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# --- Listener Rule: Forwarding to ECS ---
resource "aws_lb_listener_rule" "rr_ecs_frontend_rule" {
  listener_arn = var.gateway_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rr_frontend.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}