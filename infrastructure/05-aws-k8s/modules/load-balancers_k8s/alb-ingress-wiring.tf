# =========================================================================
# 1. Target Group: Directing Traffic to K3s Worker Nodes (Istio Ingress)
# =========================================================================
resource "aws_lb_target_group" "rr_k8s_frontend_tg" {
  name        = "rr-${var.environment}-k8s-frontend-tg"
  port        = 30080            
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"        

  health_check {
    enabled             = true
    path                = "/healthz/ready" 
    port                = "30080"
    interval            = 15               
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k8s-frontend-tg"
  })
}

# =========================================================================
# 2. DYNAMIC ATTACHMENT: Bind the Target Group to the ASG
# =========================================================================
# As the ASG scales workers up or down, they are automatically added/removed here.
resource "aws_autoscaling_attachment" "rr_k8s_frontend_asg_attach" {
  autoscaling_group_name = var.frontend_worker_asg_name
  lb_target_group_arn    = aws_lb_target_group.rr_k8s_frontend_tg.arn
}

# =========================================================================
# 3. Listener Rule Injection: 100% Cutover Interception
# =========================================================================
resource "aws_lb_listener_rule" "rr_k8s_absolute_cutover" {
  listener_arn = var.gateway_listener_arn
  priority     = 50 

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rr_k8s_frontend_tg.arn
  }

  condition {
    path_pattern {
      values = ["/*"] 
    }
  }
}