
# Network Load Balancer for HA Control Plane
resource "aws_lb" "rr_k3s_cp_nlb" {
  name               = "rr-${var.environment}-k3s-cp-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.k8s_private_subnets
  
  # THE FIX: Wire the security group to the NLB
  security_groups    = [var.nlb_sg_id]

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-cp-nlb"
  })
}

resource "aws_lb_target_group" "rr_k3s_cp_tg" {
  name        = "rr-${var.environment}-k3s-cp-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-cp-tg"
  })
}

resource "aws_lb_listener" "rr_k3s_cp_listener" {
  load_balancer_arn = aws_lb.rr_k3s_cp_nlb.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rr_k3s_cp_tg.arn
  }
}

# Control Plane Compute
resource "aws_launch_template" "rr_k3s_cp" {
  name_prefix   = "rr-${var.environment}-k3s-cp-"
  image_id      = data.aws_ami.rr_al2023.id
  instance_type = var.control_plane_type

  iam_instance_profile {
    name = var.iam_profile_control_plane
  }

  network_interfaces {
    security_groups = [var.control_plane_sg_id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data_cp.sh", {
    environment  = var.environment
    aws_region   = var.aws_region
    nlb_dns_name = aws_lb.rr_k3s_cp_nlb.dns_name
    DB_SECRET_ARN = data.aws_secretsmanager_secret.rr_db_secret.arn
  }))

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-cp-template"
  })
}

resource "aws_autoscaling_group" "rr_k3s_cp_asg" {
  name                = "rr-${var.environment}-k3s-cp-asg"
  vpc_zone_identifier = var.k8s_private_subnets
  desired_capacity    = 3 # HA Architecture
  max_size            = 3
  min_size            = 3

  launch_template {
    id      = aws_launch_template.rr_k3s_cp.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "rr-${var.environment}-k3s-control-plane"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_attachment" "rr_k3s_cp_asg_attach" {
  autoscaling_group_name = aws_autoscaling_group.rr_k3s_cp_asg.id
  lb_target_group_arn    = aws_lb_target_group.rr_k3s_cp_tg.arn
}