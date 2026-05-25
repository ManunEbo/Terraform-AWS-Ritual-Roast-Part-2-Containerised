output "ecs_execution_role_arn" {
    description = "ECS Execution role ARN - The ARN of the IAM role used by the Fargate agent"
    value = aws_iam_role.rr_ecs_execution_role.arn
}

output "ecs_task_role_arn" {
    description = "ECS task role ARN - The ARN of the IAM role used by the Fargate agent"
    value = aws_iam_role.rr_ecs_task_role.arn
}