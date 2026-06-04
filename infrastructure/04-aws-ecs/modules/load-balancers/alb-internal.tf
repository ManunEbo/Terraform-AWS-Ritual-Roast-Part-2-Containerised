# --- Internal Load Balancer ---
resource "aws_lb" "internal" {
  name               = "${var.environment}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.internal_alb_sg_id]
  subnets            = var.app_subnet_ids # Private App Subnets

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-internal-alb"
  })
}

# --- Target Group for Backend ---
resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-backend-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "5000"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"           # <-- THE GUARDRAIL
  }
}

# --- Listener for Internal API traffic ---
resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}