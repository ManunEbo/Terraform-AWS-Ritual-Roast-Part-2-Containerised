resource "aws_iam_role" "rr_k3s_worker_backend_role" {
  name = "rr-${var.environment}-k3s-worker-backend-role"

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
    Name = "rr-${var.environment}-k3s-worker-backend-role"
  })
}

resource "aws_iam_role_policy_attachment" "rr_worker_backend_ssm_attach" {
  role       = aws_iam_role.rr_k3s_worker_backend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The Backend pool gets access to the Layer 2 DB Credentials AND the Join Token
resource "aws_iam_policy" "rr_worker_backend_custom_policy" {
  name        = "rr-${var.environment}-k3s-worker-backend-policy"
  description = "Allows backend workers to access DB secrets and the K3s join token"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Effect   = "Allow"
        Resource = [
            "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-db-secret-*",
            "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-k3s-join-token-*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rr_worker_backend_custom_attach" {
  role       = aws_iam_role.rr_k3s_worker_backend_role.name
  policy_arn = aws_iam_policy.rr_worker_backend_custom_policy.arn
}

resource "aws_iam_instance_profile" "rr_k3s_worker_backend_profile" {
  name = "rr-${var.environment}-k3s-worker-backend-profile"
  role = aws_iam_role.rr_k3s_worker_backend_role.name
}