# --- Target Group for K3s Frontend Workers (Istio NodePort) ---
resource "aws_lb_target_group" "rr_k8s_frontend" {
    name        = "rr-${var.environment}-k8s-frontend-tg"
    port        = 30080 # <-- THE FIX: Point exactly at Istio's NodePort
    protocol    = "HTTP"
    vpc_id      = var.vpc_id
    target_type = "instance" # <-- Notice this is "instance" for EC2, not "ip" like Fargate!

    health_check {
      enabled             = true
      path                = "/healthz/ready" # Istio's default health endpoint
      port                = "30080"
      interval            = 30
      timeout             = 5
      healthy_threshold   = 2
      unhealthy_threshold = 2
      matcher             = "200"
    }
}

# --- Listener Rule: Forwarding to Kubernetes ---
resource "aws_lb_listener_rule" "rr_k8s_frontend_rule" {
    listener_arn = var.gateway_listener_arn
    priority     = 50 # <-- Needs to be evaluated BEFORE the ECS rule!

    action {
      type             = "forward"
      target_group_arn = aws_lb_target_group.rr_k8s_frontend.arn
    }

    condition {
      path_pattern {
        values = ["/*"]
      }
    }
}