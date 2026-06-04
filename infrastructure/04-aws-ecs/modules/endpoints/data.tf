#--------------------------------------------------------------
#  Gateway Endpoint (S3) with Zero-Trust Policy
#--------------------------------------------------------------

data "aws_iam_policy_document" "s3_gateway" {
  # 1. Allow ECR image layer pulls (Execution Role) and general reads
  statement {
    sid       = "AllowReads"
    effect    = "Allow"
    principals {
      type        = "AWS"
      identifiers = [
        var.ecs_execution_role_arn,
        var.ecs_backend_task_role_arn,
        var.ecs_frontend_task_role_arn
      ]
    }
    actions   = ["s3:Get*", "s3:List*"]
    resources = ["*"]
  }

  # 2. STRICT: Only allow the Backend Task Role to write to the App Bucket
  statement {
    sid       = "AllowAppBucketWrites"
    effect    = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.ecs_backend_task_role_arn]
    }
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${var.app_s3_bucket}",
      "arn:aws:s3:::${var.app_s3_bucket}/*"
    ]
  }
}

