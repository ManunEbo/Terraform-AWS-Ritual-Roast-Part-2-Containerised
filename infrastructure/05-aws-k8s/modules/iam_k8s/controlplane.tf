resource "aws_iam_role" "rr_k3s_control_plane_role" {
  name = "rr-${var.environment}-k3s-control-plane-role"

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
    Name = "rr-${var.environment}-k3s-cp-role"
  })
}

resource "aws_iam_role_policy_attachment" "rr_cp_ssm_attach" {
  role       = aws_iam_role.rr_k3s_control_plane_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The Control Plane requires broad access to coordinate HA and setup the GitOps mesh
resource "aws_iam_policy" "rr_cp_custom_policy" {
  name        = "rr-${var.environment}-k3s-cp-custom-policy"
  description = "Allows K3s CP to query EC2 for HA election and access required secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Required for HA Leader Election script to find peers
        Action   = ["ec2:DescribeInstances"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # Required to read ArgoCD token, DB credentials, and manage the Cluster Join Token
        Action   = [
          "secretsmanager:GetSecretValue", 
          "secretsmanager:DescribeSecret"
          # "secretsmanager:CreateSecret",
          # "secretsmanager:PutSecretValue"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-argocd-github-token-*",
          # "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-db-secret-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-k3s-join-token-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-grafana-cloud-token-*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rr_cp_custom_attach" {
  role       = aws_iam_role.rr_k3s_control_plane_role.name
  policy_arn = aws_iam_policy.rr_cp_custom_policy.arn
}

resource "aws_iam_instance_profile" "rr_k3s_cp_profile" {
  name = "rr-${var.environment}-k3s-cp-profile"
  role = aws_iam_role.rr_k3s_control_plane_role.name
}