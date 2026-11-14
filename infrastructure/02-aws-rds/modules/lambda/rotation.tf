#------------------------------------------------------------
#         Ritual Roast: Lambda Resource Definition
#------------------------------------------------------------

# Zipping index.py
data "archive_file" "rr_rotation_zip" {
  type = "zip"
  # Both files sit at the zip root; the CA bundle lands at /var/task/global-bundle.pem
  source {
    content  = file("${path.module}/index.py")
    filename = "index.py"
  }
  source {
    content  = file("${path.module}/global-bundle.pem")
    filename = "global-bundle.pem"
  }
  output_path = "${path.module}/rotation.zip"
}

# Wait for IAM eventual consistency before creating the Lambda
resource "time_sleep" "wait_for_iam" {
  create_duration = "15s"

  # This trigger ensures the timer doesn't start until the IAM Role ARN 
  # has actually been handed across the module boundary.
  triggers = {
    role_arn = var.lambda_role_arn
  }
}

resource "aws_lambda_function" "rr_secret_rotation_function" {
  function_name = "rr-${var.environment}-secret-rotation-function"
  handler       = "index.lambda_handler"
  runtime       = "python3.13"

  filename         = data.archive_file.rr_rotation_zip.output_path
  source_code_hash = data.archive_file.rr_rotation_zip.output_base64sha256

  role = var.lambda_role_arn

  layers = [aws_lambda_layer_version.rr_db_layer.arn]

  vpc_config {
    subnet_ids         = var.database_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  # Explicitly setting the memory
  memory_size = 128

  # Increasing the timeout to give the lambda enough "breathing room" to complete
  # the handshake and the multi-step database update without being cut off mid-process.
  timeout = 30

  # This forces Terraform to pause Lambda creation until the 15-second timer finishes
  depends_on = [time_sleep.wait_for_iam]
}

