# Fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "rr_al2023" {
    most_recent = true
    owners = ["amazon"]

    filter {
      name = "name"
      values = ["al2023-ami-2023.*-x86_64"]
    }
}

# ==========================================
# Control Plane: Launch Template & ASG
# ==========================================
resource "aws_launch_template" "rr_k3s_cp" {
  name_prefix   = "rr-${var.environment}-k3s-cp-"
  image_id      = data.aws_ami.rr_al2023.id
  
  # FIX: Wired to the variable instead of hardcoded
  instance_type = var.control_plane_type

  iam_instance_profile {
    name = var.iam_profile_control_plane
  }

  network_interfaces {
    security_groups = [var.control_plane_sg_id]
  }

  # Zero-Trust: Enforce IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data_cp.sh", {
    environment = var.environment
    aws_region  = var.aws_region
  }))

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-cp-template"
  })
}

resource "aws_autoscaling_group" "rr_k3s_cp_asg" {
  name                = "rr-${var.environment}-k3s-cp-asg"
  vpc_zone_identifier = var.k8s_private_subnets
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1

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

# ==========================================
# Worker Nodes: Launch Template & ASG
# ==========================================

resource "aws_launch_template" "rr_k3s_worker" {
    name_prefix   = "rr-${var.environment}-k3s-worker-"
    image_id      = data.aws_ami.rr_al2023.id
    
    # FIX: Wired to the variable instead of hardcoded
    instance_type = var.worker_node_type

    iam_instance_profile {
      name = var.iam_profile_worker
    }

    network_interfaces {
      security_groups = [var.worker_sg_id]
    }
    
    metadata_options {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    }

    user_data = base64encode(templatefile("${path.module}/user_data_worker.sh", {
        # We will pass the CP internal IP or load balancer DNS here later for cluster join
        control_plane_endpoint = "TBD"  # *****
        environment            = var.environment
        aws_region             = var.aws_region
    }))

    tags = merge(var.common_tags, {
        Name = "rr-${var.environment}-k3s-worker-template"
    })
}

resource "aws_autoscaling_group" "rr_k3s_worker_asg" {
  name                = "rr-${var.environment}-k3s-worker-asg"
  vpc_zone_identifier = var.k8s_private_subnets
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1

  # FIX: Changed from launch_configuration to launch_template
  launch_template {
    id      = aws_launch_template.rr_k3s_worker.id
    version = "$Latest"
  }

  # This tags the underlying EC2 instances directly as they boot
  tag {
    key                 = "Name"
    value               = "rr-${var.environment}-k3s-worker"
    propagate_at_launch = true
  }
}