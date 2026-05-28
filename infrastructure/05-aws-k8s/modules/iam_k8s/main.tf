# ==========================================
# 1. EC2 Trust Policy (The Handshake)
# ==========================================

data "aws_iam_policy_document" "rr_ec2_assume_role" {
    statement {
      actions = ["sts:AssumeRole"]
      principals {
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }
    }
}

# ==========================================
# 2. Control Plane Identity
# ==========================================

resource "aws_iam_role" "rr_k3s_control_plane_role" {
    name               = "rr-${var.environment}-k3s-cp-role"
    assume_role_policy = data.aws_iam_policy_document.rr_ec2_assume_role.json

    tags = merge(var.common_tags, {
        Name = "rr-${var.environment}-k3s-cp-role"
    })
}

# Grants secure terminal access via AWS Console
resource "aws_iam_role_policy_attachment" "rr_cp_ssm_core" {
    role       = aws_iam_role.rr_k3s_control_plane_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "rr_k3s_control_plane_profile" {
    name = "rr-${var.environment}-k3s-cp-profile"
    role = aws_iam_role.rr_k3s_control_plane_role.name
}

# ==========================================
# 3. Worker Node Identity
# ==========================================

resource "aws_iam_role" "rr_k3s_worker_role" {
    name               = "rr-${var.environment}-k3s-worker-role"
    assume_role_policy = data.aws_iam_policy_document.rr_ec2_assume_role.json

    tags = merge(var.common_tags, {
        Name = "rr-${var.environment}-k3s-worker-role"
    })
}

# Grants secure terminal access via AWS Console
resource "aws_iam_role_policy_attachment" "rr_worker_ssm_core" {
    role       = aws_iam_role.rr_k3s_worker_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- Custom Worker Policy: Secrets Only ---
resource "aws_iam_policy" "rr_worker_custom_policy" {
    name        = "rr-${var.environment}-k3s-worker-custom-policy"
    description = "Permissions for K3S workers to access Secrets Manager" 

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = [
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret"
                ]
                Effect   = "Allow"
                Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-db-secret-*"
            }
        ]
    })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy_attachment" "rr_worker_custom_attach" {
    role       = aws_iam_role.rr_k3s_worker_role.name
    policy_arn = aws_iam_policy.rr_worker_custom_policy.arn
}

resource "aws_iam_instance_profile" "rr_k3s_worker_profile" {
    name = "rr-${var.environment}-k3s-worker-profile"
    role = aws_iam_role.rr_k3s_worker_role.name
}