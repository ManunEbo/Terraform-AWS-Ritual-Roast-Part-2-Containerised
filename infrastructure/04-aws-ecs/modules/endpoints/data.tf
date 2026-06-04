#--------------------------------------------------------------
#  Gateway Endpoint (S3) with Zero-Trust Policy
#--------------------------------------------------------------

#--------------------------------------------------------------
#  Gateway Endpoint (S3) with Strict Zero-Trust Policy
#--------------------------------------------------------------

data "aws_iam_policy_document" "s3_gateway" {
  # 1. Allow ECR image layer pulls and general reads for specific roles
  statement {
    sid       = "AllowReads"
    effect    = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"] # AWS requires this to be * in VPC endpoint policies...
    }
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["*"]
    
    # ...and enforces the Identity lockdown here instead:
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [
        var.ecs_execution_role_arn,
        var.ecs_backend_task_role_arn,
        var.ecs_frontend_task_role_arn
      ]
    }
  }

  # 2. STRICT: Only allow the Backend Task Role to write to the App Bucket
  statement {
    sid       = "AllowAppBucketWrites"
    effect    = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${var.app_s3_bucket}",
      "arn:aws:s3:::${var.app_s3_bucket}/*"
    ]
    
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [var.ecs_backend_task_role_arn]
    }
  }
}

