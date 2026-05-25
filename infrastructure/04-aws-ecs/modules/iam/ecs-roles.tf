#--------------------------------------------------------------
# Ritual Roast - ECS Execution Role
# (The "Passport" for Fargate to pull images & logs)
#--------------------------------------------------------------

resource "aws_iam_role" "rr_ecs_execution_role" {
  name = "rr-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      # FIXED: Capitalized 'Service'
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-ecs-execution-role"
  })
}

# Standard AWS Managed Policy for ECS Execution
resource "aws_iam_role_policy_attachment" "rr_ecs_execution_standard" {
  role       = aws_iam_role.rr_ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#--------------------------------------------------------------
# Ritual Roast - ECS Task Role
# (What the code INSIDE the container is allowed to do)
#--------------------------------------------------------------
resource "aws_iam_role" "rr_ecs_task_role" {
  name = "rr-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      # FIXED: Capitalized 'Service'
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# --- custom policy ---
# This defines what the app can do
resource "aws_iam_policy" "rr_backend_task_policy" {
  name        = "rr-${var.environment}-backend-task-policy"
  description = "Permissions for the Ritual Roast backend to access specific AWS services"
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
        # SECURE & CYCLE-FREE: Locks down to this account, region, and environment prefix!
        Resource = ["arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:rr-${var.environment}-db-secret-*"]
      },
      {
        # Allow the backend to talk to s3
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        # FIXED: Replaced db_secret_arn with the proper S3 bucket ARNs
        Resource = [
          "arn:aws:s3:::${var.s3_bucket}",
          "arn:aws:s3:::${var.s3_bucket}/*"
        ]
      }
    ]
  })
}

# --- Attach rr_backend_task_policy to rr_ecs_tasks_role
# This "glues" the permissions to the role
resource "aws_iam_role_policy_attachment" "rr_task_role_attachment" {
  role       = aws_iam_role.rr_ecs_task_role.name
  policy_arn = aws_iam_policy.rr_backend_task_policy.arn
}