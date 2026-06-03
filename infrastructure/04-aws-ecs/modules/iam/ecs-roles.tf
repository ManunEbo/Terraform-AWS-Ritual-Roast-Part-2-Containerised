#--------------------------------------------------------------
# Ritual Roast - ECS Execution Role (Shared)
# (The "Passport" for Fargate to pull images & logs)
#--------------------------------------------------------------

resource "aws_iam_role" "rr_ecs_execution_role" {
  name = "rr-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-ecs-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "rr_ecs_execution_standard" {
  role       = aws_iam_role.rr_ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#--------------------------------------------------------------
# Ritual Roast - BACKEND Task Role
# (What the Flask API is allowed to do)
#--------------------------------------------------------------
resource "aws_iam_role" "rr_ecs_backend_task_role" {
  name = "rr-${var.environment}-ecs-backend-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "rr_backend_task_policy" {
  name        = "rr-${var.environment}-backend-task-policy"
  description = "Permissions for the Ritual Roast backend to access DB Secrets and S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow the backend to get secrets
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = ["arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:rr-${var.environment}-db-secret-*"]
      },
      {
        # Allow the backend to talk to S3
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket}",
          "arn:aws:s3:::${var.s3_bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rr_backend_task_role_attachment" {
  role       = aws_iam_role.rr_ecs_backend_task_role.name
  policy_arn = aws_iam_policy.rr_backend_task_policy.arn
}

#--------------------------------------------------------------
# Ritual Roast - FRONTEND Task Role
# (What the Next.js App is allowed to do)
#--------------------------------------------------------------
resource "aws_iam_role" "rr_ecs_frontend_task_role" {
  name = "rr-${var.environment}-ecs-frontend-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
