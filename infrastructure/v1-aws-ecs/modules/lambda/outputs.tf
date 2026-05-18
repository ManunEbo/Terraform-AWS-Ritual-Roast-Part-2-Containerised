output "lambda_function_arn" {
  description = "The ARN of the Secret Rotation Lambda Function"
  # Ensure this matches the exact resource name in your lambda module!
  value = aws_lambda_function.rr_secret_rotation_function.arn
}