resource "aws_launch_template" "rr_k3s_worker_frontend" {
  name_prefix   = "rr-${var.environment}-k3s-worker-frontend-"
  image_id      = data.aws_ami.rr_al2023.id
  instance_type = var.worker_node_type

  iam_instance_profile {
    name = var.iam_profile_worker_frontend
  }

  network_interfaces {
    security_groups = [var.worker_frontend_sg_id]
  }
    
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user_data_worker_frontend.sh", {
    control_plane_endpoint = aws_lb.rr_k3s_cp_nlb.dns_name
    environment            = var.environment
    aws_region             = var.aws_region
    node_role              = "frontend"
  }))

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-worker-frontend-template"
  })
}

resource "aws_autoscaling_group" "rr_k3s_worker_frontend_asg" {
  name                = "rr-${var.environment}-k3s-worker-frontend-asg"
  vpc_zone_identifier = var.k8s_private_subnets
  desired_capacity    = 1
  max_size            = 4
  min_size            = 1

  launch_template {
    id      = aws_launch_template.rr_k3s_worker_frontend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "rr-${var.environment}-k3s-worker-frontend"
    propagate_at_launch = true
  }
}