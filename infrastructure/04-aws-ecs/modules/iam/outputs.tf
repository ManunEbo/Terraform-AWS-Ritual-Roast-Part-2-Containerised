output "ecs_execution_role_arn" {
  description = "ECS Execution role ARN"
  value       = aws_iam_role.rr_ecs_execution_role.arn
}

output "ecs_backend_task_role_arn" {
  description = "Backend ECS task role ARN"
  value       = aws_iam_role.rr_ecs_backend_task_role.arn
}

output "ecs_frontend_task_role_arn" {
  description = "Frontend ECS task role ARN"
  value       = aws_iam_role.rr_ecs_frontend_task_role.arn
}