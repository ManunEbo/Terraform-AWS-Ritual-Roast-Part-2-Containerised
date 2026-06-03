resource "aws_launch_template" "rr_k3s_worker_backend" {
  name_prefix   = "rr-${var.environment}-k3s-worker-backend-"
  image_id      = data.aws_ami.rr_al2023.id
  instance_type = var.worker_node_type

  iam_instance_profile {
    name = var.iam_profile_worker_backend
  }

  network_interfaces {
    security_groups = [var.worker_backend_sg_id]
  }
    
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data_worker_backend.sh", {
    control_plane_endpoint = aws_lb.rr_k3s_cp_nlb.dns_name
    environment            = var.environment
    aws_region             = var.aws_region
    node_role              = "backend"
  }))

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-worker-backend-template"
  })
}

resource "aws_autoscaling_group" "rr_k3s_worker_backend_asg" {
  name                = "rr-${var.environment}-k3s-worker-backend-asg"
  vpc_zone_identifier = var.k8s_private_subnets
  desired_capacity    = 2
  max_size            = 5
  min_size            = 2

  launch_template {
    id      = aws_launch_template.rr_k3s_worker_backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "rr-${var.environment}-k3s-worker-backend"
    propagate_at_launch = true
  }
}