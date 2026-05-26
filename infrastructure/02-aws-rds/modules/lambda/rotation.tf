#------------------------------------------------------------
#         Ritual Roast: Lambda Resource Definition
#------------------------------------------------------------

# Zipping index.py
data "archive_file" "rr_rotation_zip" {
  type = "zip"
  # Since index.py is in the same folder as this .tf file
  source_file = "${path.module}/index.py"
  output_path = "${path.module}/rotation.zip"
}

# --- ADDED: The IAM Eventual Consistency Speed Bump ---
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
  runtime       = "python3.9"

  # FIXED: Pointing to the automated zip created above, removing S3 references
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

  # --- ADDED: The Dependency Chain ---
  # This forces Terraform to pause Lambda creation until the 15-second timer finishes
  depends_on = [time_sleep.wait_for_iam]
}

# CRITICAL: Lambda resource-based policy
# This allows secrets manager to invoke the lambda function.
resource "aws_lambda_permission" "rr_allow_secretsmanager_to_call_lambda" {
    statement_id  = "AllowExecutionFromSecretsManager"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.rr_secret_rotation_function.function_name
    # FIXED: Added "aws" to the domain
    principal     = "secretsmanager.amazonaws.com" 
}