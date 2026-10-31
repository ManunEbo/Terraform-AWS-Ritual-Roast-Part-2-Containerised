#------------------------------------------------------------
#           Ritual Roast: Lambda Execution Role
#------------------------------------------------------------

# 1. The Core IAM Role
resource "aws_iam_role" "rr_lambda_secrets_role" {
  name = "rr-${var.environment}-lambda-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        # FIXED: Capitalized 'Service'
        Service = "lambda.amazonaws.com"
      }
      Effect = "Allow"
      Sid    = ""
    }]
  })

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-lambda-secrets-role"
  })
}

# 2. Managed policy for VPC access (critical for accessing RDS)
resource "aws_iam_role_policy_attachment" "rr_lambda_vpc_access" {
  role       = aws_iam_role.rr_lambda_secrets_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# 3. Managed policy for basic execution (CloudWatch logs)
resource "aws_iam_role_policy_attachment" "rr_lambda_basic_execution" {
  role       = aws_iam_role.rr_lambda_secrets_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 4. Custom policy for Secrets Manager and CloudWatch metrics
resource "aws_iam_policy" "rr_lambda_secrets_custom_policy" {
  name = "rr-${var.environment}-lambda-secrets-manager-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:UpdateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecretVersionStage" #  Permits shifting the "AWSCURRENT" label
      ]
      # FIXED: Capitalized 'Resource'
      Resource = "arn:aws:secretsmanager:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:secret:rr-${var.environment}-db-secret-*"
      },
      {
        # Allow lambda to write metrics to CloudWatch Metrics
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# 5. Attach the custom policy above
resource "aws_iam_role_policy_attachment" "rr_custom_policy_attach" {
  role       = aws_iam_role.rr_lambda_secrets_role.name
  policy_arn = aws_iam_policy.rr_lambda_secrets_custom_policy.arn
}