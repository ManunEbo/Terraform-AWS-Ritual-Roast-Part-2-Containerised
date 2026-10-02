# Layer 04-aws-ecs — HLD inventory

Scope: ECS/Fargate frontend+backend, internal ALB, CW log groups,
VPC interface endpoints (ECR/Logs), S3 Gateway endpoint, IAM task
roles, Layer-4 SG chain. Injects a listener rule into the Layer-1
public ALB listener.

## Approved decisions
- Draw the full user-path SG chain at the bottom:
  `0.0.0.0/0 → public-alb-sg :80 → frontend-sg :3000 → internal-alb-sg :80
  → backend-sg :5000 → database-sg :3306` (database SG shown as external;
  the ingress-from-backend rule is drawn as "injected into L2").
- VPC Interface endpoints (`ecr.api`, `ecr.dkr`, `logs`) grouped
  in a small sub-cluster of the App subnet column.
- Keep CloudWatch icon on this layer (CW log groups are owned here).
- Layer-4 S3 Gateway endpoint drawn with an "orphan" annotation
  because its `route_table_ids` resolves to `[]` (see Findings).

## Components

### ECS cluster, services, tasks
- `aws_ecs_cluster.rr_ecs_cluster` — `modules/ecs/cluster.tf` —
  `rr-dev-ecs-cluster`, `containerInsights=enabled`.
- `aws_ecs_cluster_capacity_providers.rr_ecs_cp` —
  providers `FARGATE`, `FARGATE_SPOT`, default base=1 weight=100 FARGATE.
- `aws_ecs_task_definition.rr_frontend_task` — `modules/ecs/tasks.tf` —
  `awsvpc`, FARGATE, cpu 512 mem 1024,
  execution role `ecs_execution_role_arn`,
  task role `ecs_frontend_task_role_arn`,
  container `rr-frontend-container-01`
  (image `.../rr-dev-frontend:latest`, port 3000,
  `readonlyRootFilesystem=true`, volume `nextjs-cache` mounted at
  `/app/.next/cache`), env `BACKEND_URL=http://<internal-alb>`,
  log group `/ecs/rr-dev-frontend`.
- `aws_ecs_task_definition.rr_backend_task` — cpu 256 mem 512,
  task role `ecs_backend_task_role_arn`,
  container `rr-backend-container-01` (image `.../rr-dev-backend:latest`,
  port 5000, read-only root FS),
  env `SECRET_ARN`, `AWS_REGION`, log group `/ecs/rr-dev-backend`.
- `aws_ecs_service.rr_frontend_service` — `modules/ecs/services.tf` —
  desired 2, FARGATE weight=1 base=1, `health_check_grace_period_seconds=120`,
  `assign_public_ip=false`, Web subnets + frontend SG,
  load_balancer target `frontend_tg_arn` port 3000,
  `ignore_changes=[task_definition, desired_count]`.
- `aws_ecs_service.rr_backend_service` — desired 2, `FARGATE_SPOT` weight=1,
  App subnets + backend SG, target `backend_tg_arn` port 5000.

### Load balancers
- `aws_lb.internal` — `modules/load-balancers/alb-internal.tf` —
  `dev-internal-alb`, internal, in App subnets, SG `internal_alb_sg_id`.
- `aws_lb_target_group.backend` — port 5000 HTTP, target_type `ip`,
  health check `/health` port 5000 matcher 200.
- `aws_lb_listener.internal_http` — :80 forward to `backend` TG.
- `aws_lb_target_group.rr_frontend` — `modules/load-balancers/alb-wiring.tf` —
  `rr-dev-ecs-frontend-tg`, port 3000 HTTP, target_type `ip`,
  health check `/api/health` port 3000 matcher 200.
- `aws_lb_listener_rule.rr_ecs_frontend_rule` — attaches to Layer-1
  listener (`var.gateway_listener_arn`), priority 100,
  `path_pattern = ["/*"]` → forward `rr_frontend` TG.
  INJECTED into Layer 1.

### VPC endpoints
- `aws_vpc_endpoint.ecr_api` — `modules/endpoints/endpoints.tf` —
  Interface in App subnets, `private_dns_enabled`, SG `endpoints_sg_id`.
- `aws_vpc_endpoint.ecr_dkr` — Interface in App subnets.
- `aws_vpc_endpoint.logs` — Interface in App subnets.
- `aws_vpc_endpoint.s3` — Gateway, `route_table_ids = var.route_table_ids`
  (see Findings — resolves to `[]`), with
  `policy = data.aws_iam_policy_document.s3_gateway.json`.

### CloudWatch
- `aws_cloudwatch_log_group.rr_frontend_logs` —
  `modules/ecs/log-groups.tf` — `/ecs/rr-dev-frontend`, 7-day retention.
- `aws_cloudwatch_log_group.rr_backend_logs` —
  `/ecs/rr-dev-backend`, 7-day retention.

### IAM (shown in an "IAM" box outside the VPC)
- `aws_iam_role.rr_ecs_execution_role` + managed
  `AmazonECSTaskExecutionRolePolicy` — `modules/iam/ecs-roles.tf`.
- `aws_iam_role.rr_ecs_backend_task_role` + inline
  `aws_iam_policy.rr_backend_task_policy`
  (`secretsmanager:GetSecretValue|DescribeSecret` on
  `rr-${env}-db-secret-*`). Zero-trust split from frontend.
- `aws_iam_role.rr_ecs_frontend_task_role` — no attached permissions
  (frontend has no need for DB secret).

## Security groups
- `aws_security_group.rr_frontend` (name `rr-dev-frontend-sg`) —
  `modules/security_groups/sg-web-tier.tf`.
  - Ingress 3000 from Layer-1 `public_alb_sg` —
    `aws_security_group_rule.rr_frontend_from_public_alb`.
  - Egress 80 to `rr_internal_alb` SG —
    `aws_security_group_rule.rr_frontend_to_internal_alb`.
  - Egress 443 to `rr_endpoints_sg` —
    `aws_security_group_rule.rr_frontend_egress_to_endpoints`.
  - Egress 443 to S3 prefix list —
    `aws_security_group_rule.rr_frontend_egress_to_s3`.
- `aws_security_group.rr_internal_alb` (name `rr-dev-internal-alb-sg`) —
  `modules/security_groups/sg-internal-alb.tf`.
  - Ingress 80 from `rr_frontend` SG —
    `aws_security_group_rule.rr_int_alb_from_frontend`.
  - Egress 5000 to `rr_backend` SG —
    `aws_security_group_rule.int_alb_to_backend`.
- `aws_security_group.rr_backend` (name `rr-dev-backend-sg`) —
  `modules/security_groups/sg-app-tier.tf`.
  - Ingress 5000 from `rr_internal_alb` SG —
    `aws_security_group_rule.backend_from_internal_alb`.
  - Egress 3306 to Layer-2 `database_sg` —
    `aws_security_group_rule.backend_to_db`.
  - Egress 443 to `rr_endpoints_sg` —
    `aws_security_group_rule.rr_backend_egress_to_endpoints`.
  - Egress 443 to S3 prefix list —
    `aws_security_group_rule.rr_backend_egress_to_s3`.

## Cross-layer references (data sources)
- `data.aws_region.current`.
- `data.aws_vpc.rr_vpc` (tag match on `rr-${env}-*`).
- `data.aws_subnets.public_subnets` — `PublicSubnet-*`.
- `data.aws_subnets.web_subnets` — `WebSubnet-*`.
- `data.aws_subnets.AppSubnets` — `AppSubnet-*`.
- `data.aws_security_group.public_alb_sg` — name `rr-${env}-alb-sg` (L1).
- `data.aws_security_group.rr_endpoints_sg` — tag `rr-${env}-vpc-endpoints-sg` (L1).
- `data.aws_security_group.database_sg` — tag `rr-${env}-database-sg` (L2).
- `data.aws_secretsmanager_secret.rr_db_secret` — name `rr-${env}-db-secret` (L2).
- `data.aws_lb.gateway_alb` + `data.aws_lb_listener.gateway_http_listener` —
  L1 public ALB listener on port 80.
- `data.aws_route_tables.private_rts` — filter `tag:Tier=app` (see Findings).

## Rules this layer injects into other layers
- INTO Layer-1 `public_alb_sg`:
  egress 3000 to `rr_frontend` SG —
  `aws_security_group_rule.alb_allow_outbound_to_frontend`
  (`modules/security_groups/sg-web-tier.tf`).
- INTO Layer-2 `database_sg`:
  ingress 3306 from `rr_backend` SG —
  `aws_security_group_rule.db_ingress_from_backend`
  (`modules/security_groups/sg-app-tier.tf`).
- INTO Layer-1 `rr-dev-vpc-endpoints-sg`:
  - ingress 443 from `rr_backend` —
    `aws_security_group_rule.rr_endpoints_ingress_from_backend`.
  - ingress 443 from `rr_frontend` —
    `aws_security_group_rule.rr_endpoints_ingress_from_frontend`
    (`modules/security_groups/sg-endpoints.tf`).
- INTO Layer-1 public ALB listener:
  `aws_lb_listener_rule.rr_ecs_frontend_rule`, priority 100,
  `/* → rr_frontend` TG.

## Findings (not fixed)
- Layer 4's S3 Gateway endpoint has `route_table_ids = []` —
  `data.aws_route_tables.private_rts` filters by `tag:Tier=app`, and
  no route table in this VPC carries a `Tier` tag. The endpoint is
  created but attaches to no route table.
- Layer 1's S3 Gateway endpoint attaches to the shared private RT and
  serves Web/App/Database subnets; this layer's duplicate is orphan.
