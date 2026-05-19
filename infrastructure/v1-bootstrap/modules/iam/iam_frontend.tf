resource "aws_iam_role" "rr_github_frontend_role" {
  name = "rr-${var.environment}-github-frontend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "rr_github_frontend_policy" {
  name = "rr-${var.environment}-github-frontend-policy"
  role = aws_iam_role.rr_github_frontend_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowECRLogin",
        Effect   = "Allow",
        Action   = "ecr:GetAuthorizationToken",
        Resource = "*"
      },
      {
        Sid    = "AllowPushToFrontendRepoOnly",
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ],
        Resource = var.frontend_repo_arn
      }
    ]
  })
}