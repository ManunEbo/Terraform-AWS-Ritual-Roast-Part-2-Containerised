resource "aws_iam_role" "rr_k3s_worker_frontend_role" {
  name = "rr-${var.environment}-k3s-worker-frontend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-k3s-worker-frontend-role"
  })
}

resource "aws_iam_role_policy_attachment" "rr_worker_frontend_ssm_attach" {
  role       = aws_iam_role.rr_k3s_worker_frontend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Frontend ONLY gets access to the Cluster Join Token
resource "aws_iam_policy" "rr_worker_frontend_custom_policy" {
  name        = "rr-${var.environment}-k3s-worker-frontend-policy"
  description = "Allows frontend workers to fetch the K3s join token"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Effect   = "Allow"
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-k3s-join-token-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rr_worker_frontend_custom_attach" {
  role       = aws_iam_role.rr_k3s_worker_frontend_role.name
  policy_arn = aws_iam_policy.rr_worker_frontend_custom_policy.arn
}

resource "aws_iam_instance_profile" "rr_k3s_worker_frontend_profile" {
  name = "rr-${var.environment}-k3s-worker-frontend-profile"
  role = aws_iam_role.rr_k3s_worker_frontend_role.name
}