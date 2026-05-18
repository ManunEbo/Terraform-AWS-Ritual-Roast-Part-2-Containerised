output "cluster_name" {
  description = "The name of the Ritual Roast ECS Cluster"
  value       = aws_ecs_cluster.rr_ecs_cluster.name
}

output "cluster_arn" {
  description = "The ARN of the Ritual Roast ECS Cluster"
  value       = aws_ecs_cluster.rr_ecs_cluster.arn
}

output "frontend_task_definition_arn" {
  description = "The ARN of the frontend task definition"
  value       = aws_ecs_task_definition.rr_frontend_task.arn
}

output "backend_task_definition_arn" {
  description = "The ARN of the backend task definition"
  value       = aws_ecs_task_definition.rr_backend_task.arn
}

output "frontend_log_group_name" {
  description = "The CloudWatch log group for the frontend"
  value       = aws_cloudwatch_log_group.rr_frontend_logs.name
}

output "backend_log_group_name" {
  description = "The CloudWatch log group for the backend"
  value       = aws_cloudwatch_log_group.rr_backend_logs.name
}

output "frontend_service_name" {
  description = "The name of the frontend ecs service"
  value       = aws_ecs_service.rr_frontend_service.name
}

output "backend_service_name" {
  description = "The name of the backend ecs service"
  value       = aws_ecs_service.rr_backend_service.name
}

output "frontend_service_id" {
  description = "The ID/ARN of the frontend ecs service"
  value       = aws_ecs_service.rr_frontend_service.id
}

output "backend_service_id" {
  description = "The ID/ARN of the backend ecs service"
  value       = aws_ecs_service.rr_backend_service.id
}