#--- Public Load Balancer ---
# This ALB handles the "Front Door" of your application
resource "aws_lb" "rr_public" {
  name               = "rr-${var.environment}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.public_alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = merge(var.common_tags, {
    Name = "rr-${var.vpc_name}-public-alb"
  })
}

# #--- Target Group for Frontend ---
# We commented this out because we were going to use the target groups from ECS
# This made the ALB a flexible front door for both ECS and K8S
# resource "aws_lb_target_group" "rr_frontend" {
#   name        = "rr-${var.environment}-frontend-tg"
#   port        = 3000
#   protocol    = "HTTP" # Why is this not HTTPS, is it because we need an ssl certificate
#   vpc_id      = var.vpc_id
#   target_type = "ip" # Required for Fargate

#   health_check {
#     enabled             = true
#     path                = "/"
#     port                = "3000"
#     interval            = 30
#     timeout             = 5
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#   }

#   tags = merge(var.common_tags, {
#     Name = "rr-${var.environment}-frontend-tg"
#   })
# }

#--- Listener for HTTP ---
# resource "aws_lb_listener" "public_http" {
#   load_balancer_arn = aws_lb.public.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.rr_frontend.arn
#   }
# }

#--- Default Listener (The Catch-all) ---
# This listener catches any traffic that DOES NOT match an ECS or K8s rule
resource "aws_lb_listener" "rr_public_http" {
  load_balancer_arn = aws_lb.rr_public.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: Service Not Found. Welcome to the Ritual Roast Gateway."
      status_code  = "404"
    }
  }
}