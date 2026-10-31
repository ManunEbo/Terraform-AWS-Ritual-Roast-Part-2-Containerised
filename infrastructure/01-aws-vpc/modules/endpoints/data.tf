data "aws_iam_policy_document" "s3_ecr_layers" {
  statement {
    sid    = "AllowEcrImageLayersOnly"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::prod-${var.aws_region}-starport-layer-bucket/*"]
  }
}