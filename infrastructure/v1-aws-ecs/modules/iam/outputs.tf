output "ecs_execution_role_arn" {
  description = "The ARN of the ECS task execution role (for Fargate infrastructure)"
  value       = aws_iam_role.rr_ecs_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "The ARN of the ECS task role (for application code permissions)"
  value       = aws_iam_role.rr_ecs_task_role.arn
}

output "lambda_role_arn" {
  description = "The lambda role ARN"
  value       = aws_iam_role.rr_lambda_secrets_role.arn
}