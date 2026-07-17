# Layer 4 — ECS, Fargate & the Internal Load Balancer

This is where the application actually runs, for this project's ECS deployment story: it takes the
shared front door from `infrastructure/01-aws-vpc`, the database from `infrastructure/02-aws-rds`,
and the container images from `infrastructure/03-aws-ecr`, and turns them into two running,
load-balanced, self-healing services — a frontend and a backend, each with two replicas, on AWS
Fargate (containers with no servers to patch or manage — AWS runs the underlying compute for you).

## What this layer builds

| Module | Creates |
|---|---|
| `modules/ecs` | The ECS cluster, and Fargate task definitions + services for the frontend and backend. |
| `modules/load-balancers` | A second, **internal** load balancer for frontend→backend traffic, plus this layer's own routing rule attached onto the shared public ALB from layer 1. |
| `modules/iam` | One shared "execution" role, and two deliberately unequal "task" roles. |
| `modules/endpoints` | Additional private AWS API access (ECR, CloudWatch Logs) for Fargate tasks that have no NAT gateway. |
| `modules/security_groups` | Four security groups chaining every hop from the public internet down to the database. |

## The traffic path: two load balancers, not one

```
Internet
   │
   ▼
Public ALB  (layer 1's shared ALB, port 80)
   │  this layer's own rule — priority 100, path "/*"
   ▼
Frontend target group :3000   (health check: GET /api/health)
   │
   ▼
Frontend Fargate task  (Next.js — 512 CPU / 1024 MB, 2 tasks, on-demand)
   │  BACKEND_URL = http://<internal ALB DNS name>
   ▼
Internal ALB  (private — no public IP, no internet route)
   │
   ▼
Backend target group :5000   (health check: GET /health)
   │
   ▼
Backend Fargate task  (Flask — 256 CPU / 512 MB, 2 tasks, Spot)
   │
   ▼
RDS MySQL  (layer 2)
```

Two load balancers, not one, because they solve different problems. The public ALB is *shared*
across this entire project (layer 5's Kubernetes stack reuses the exact same one), so it can't be
where ECS-specific, private routing details live. The internal ALB exists purely so the frontend
task has one stable, private address to call the backend at — a much simpler answer than standing up
a service-discovery system (like AWS Cloud Map) just to let one task find another.

## Walking through the layer

### 1. The cluster: Fargate everywhere, Spot where it's safe

```hcl
resource "aws_ecs_cluster" "rr_ecs_cluster" {
  setting { name = "containerInsights"; value = "enabled" }
}
resource "aws_ecs_cluster_capacity_providers" "rr_ecs_cp" {
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy { base = 1; weight = 100; capacity_provider = "FARGATE" }
}
```

`containerInsights` turns on detailed per-task CloudWatch metrics (CPU, memory, network) with no
extra instrumentation needed in the app code. The cluster registers *both* Fargate and Fargate
Spot as available capacity — but each **service** below picks its own strategy, and the two services
disagree on purpose:

- The **frontend** service pins to plain `FARGATE` (on-demand) — user-facing traffic shouldn't be
  interrupted by a Spot reclamation mid-request.
- The **backend** service runs on `FARGATE_SPOT` — the source comment says it plainly:
  *"Cost-saving for development!"* An internal API, called only by the frontend and never directly
  by a user's browser, tolerates an occasional Spot interruption far more comfortably (ECS simply
  reschedules the task elsewhere) in exchange for a substantial discount over on-demand pricing.

### 2. Task definitions: different sizes, and very different privilege levels

```hcl
resource "aws_ecs_task_definition" "rr_frontend_task" {
  cpu = 512; memory = 1024                       # Next.js needs headroom for the node server + build cache
  task_role_arn = var.ecs_frontend_task_role_arn  # ZERO-TRUST FIX: no DB secret access
  volume { name = "nextjs-cache" }
  container_definitions = jsonencode([{
    readonlyRootFilesystem = true
    mountPoints = [{ sourceVolume = "nextjs-cache", containerPath = "/app/.next/cache", readOnly = false }]
    environment = [{ name = "BACKEND_URL", value = "http://${var.internal_alb_dns_name}" }]
  }])
}

resource "aws_ecs_task_definition" "rr_backend_task" {
  cpu = 256; memory = 512                         # a lean Flask API
  task_role_arn = var.ecs_backend_task_role_arn    # ZERO-TRUST FIX: has DB secret access
  container_definitions = jsonencode([{
    readonlyRootFilesystem = true
    environment = [
      { name = "SECRET_ARN", value = data.aws_secretsmanager_secret.rr_db_secret.arn },
      { name = "AWS_REGION", value = data.aws_region.current.id }
    ]
  }])
}
```

Both containers run with **`readonlyRootFilesystem = true`** — the container's own filesystem can't
be written to at all at runtime, closing off an entire category of "attacker writes a file to disk"
post-exploitation techniques. The frontend needs exactly one exception to that rule: Next.js's image
optimisation cache at `/app/.next/cache` genuinely needs to be writable, so a small **ephemeral
Fargate volume** is mounted at that one path and nowhere else — the rest of the filesystem stays
locked. The backend needs no exception at all, and that's not an oversight: as covered in
`apps/v1-backend-flask/README-1.md`, Gunicorn's own heartbeat files are explicitly redirected to
`/dev/shm` (an in-memory filesystem) rather than the container's root filesystem in that app's
Dockerfile — the two decisions, made in two different layers of this project, are two ends of the
same design.

`BACKEND_URL` and `SECRET_ARN` are both injected as plain environment variables here — neither is a
secret itself, just a pointer (a DNS name, an ARN); see `infrastructure/02-aws-rds/README.md` for why
the *actual* database credentials are never handled this way.

### 3. IAM: one shared passport, two unequal task roles

```hcl
# Execution role — shared by both tasks. "The passport for Fargate to pull images & logs."
resource "aws_iam_role_policy_attachment" "rr_ecs_execution_standard" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Backend task role — scoped to exactly one secret and one bucket
resource "aws_iam_policy" "rr_backend_task_policy" {
  policy = jsonencode({ Statement = [
    { Action = ["secretsmanager:GetSecretValue", "DescribeSecret"], Resource = ["arn:...:secret:rr-${var.environment}-db-secret-*"] },
    { Action = ["s3:GetObject", "PutObject", "ListBucket"], Resource = ["arn:...:${var.s3_bucket}", "arn:...:${var.s3_bucket}/*"] }
  ]})
}

# Frontend task role — exists, and gets NO custom policy at all
resource "aws_iam_role" "rr_ecs_frontend_task_role" { ... }
```

The **execution role** is infrastructure-level plumbing every task needs regardless of what it does
(pull the image, write logs) — it's shared because scoping it per-task would add complexity without
any security benefit, since it never grants access to *application* data.

The **task roles** are where the real access-control decision lives, and they're deliberately
unequal. The backend's task role can read exactly one secret (matching the ARN pattern from layer 2)
and reach exactly one S3 bucket — nothing else. The frontend's task role, by contrast, has **no
custom policy attached to it at all** — it exists only because Fargate requires every task to have
one, and the source code labels this explicitly: *"ZERO-TRUST FIX: Frontend gets its own isolated
role (No DB Secret Access)."* If the frontend container were ever compromised, the AWS credentials it
could assume grant it nothing. This lines up exactly with what `apps/v1-frontend-nextjs`'s own code
does: the frontend never calls an AWS SDK for anything, so an empty IAM role isn't a missing feature —
it's the permissions correctly mirroring the fact that the frontend has no legitimate reason to touch
AWS APIs in the first place.

### 4. Services: the "breathing room" fix, and handing deployment ownership to CI

```hcl
resource "aws_ecs_service" "rr_frontend_service" {
  desired_count = 2
  health_check_grace_period_seconds = 120   # "This is a huge culprit for the failures"
  capacity_provider_strategy { capacity_provider = "FARGATE"; weight = 1; base = 1 }
  lifecycle { ignore_changes = [task_definition, desired_count] }
}
```

**`health_check_grace_period_seconds = 120`** exists because of a real, specific failure mode: the
moment ECS places a new task, the ALB starts health-checking it immediately — but a Next.js or Flask
process needs a few seconds to actually finish booting before it can answer that check at all.
Without this grace period, ECS sees the first few checks fail, concludes the task is broken, and
kills and replaces it — before it was ever given the chance to become healthy. That's a self-inflicted
restart loop on *every single deployment*, which is exactly what the source comment is flagging as
"a huge culprit for the failures."

**`lifecycle { ignore_changes = [task_definition, desired_count] }`** is a deliberate hand-off: once
the service exists, Terraform stops trying to enforce which exact task-definition revision is
running or how many tasks are desired. That's what allows a separate process — a CI/CD pipeline
pushing a new image and registering a new task-definition revision, or someone manually scaling the
service for a load test — to operate the service day to day, without every subsequent
`terraform apply` fighting to reset it back to whatever was true the moment this resource was first
created. Terraform owns the *shape* of the service; something else owns its *day-to-day state*.

### 5. The internal ALB and this layer's rule on the shared one

```hcl
# alb-internal.tf — private, backend-only
resource "aws_lb" "internal" { internal = true; subnets = var.app_subnet_ids }
resource "aws_lb_target_group" "backend" {
  port = 5000
  health_check { path = "/health"; matcher = "200" }
}

# alb-wiring.tf — this layer's rule on LAYER 1's shared public ALB
resource "aws_lb_target_group" "rr_frontend" {
  port = 3000
  health_check { path = "/api/health"; matcher = "200" }  # the shallow route, not the backend
}
resource "aws_lb_listener_rule" "rr_ecs_frontend_rule" {
  listener_arn = var.gateway_listener_arn
  priority     = 100
  condition { path_pattern { values = ["/*"] } }
  action      { type = "forward"; target_group_arn = aws_lb_target_group.rr_frontend.arn }
}
```

The frontend's health check on the *public* ALB deliberately points at `/api/health` — the shallow
Next.js route that never calls the backend (see `apps/v1-frontend-nextjs/README.md`) — so a slow or
struggling backend can never make the ALB conclude the *frontend* is unhealthy and pull it from
rotation. **Priority 100** on this listener rule is a specific, deliberate number: it leaves room for
`infrastructure/05-aws-k8s` to later attach its own rule at **priority 10** on the same shared
listener. The two never actually compete for traffic (this project destroys layers 3–4 before
deploying layer 5), but the priority gap means that if they were ever both present, the Kubernetes
rule would win — a small piece of leftover-proofing for a scenario the deploy sequence is designed to
avoid in the first place.

### 6. VPC endpoints: reaching AWS with still no NAT gateway

As established in `infrastructure/01-aws-vpc/README.md`, this project's private subnets have no NAT
gateway anywhere in layers 1–4 — everything they need reaches AWS over private VPC endpoints
instead. Fargate tasks running in this layer's private subnets need to pull their own container image
from ECR and write logs to CloudWatch; this layer's `modules/endpoints` adds the ECR API, ECR Docker,
and CloudWatch Logs interface endpoints for exactly that — plus its own S3 gateway endpoint (carrying
a locked-down, identity-scoped access policy), because ECR stores the actual image *layers* in S3, so
pulling an image needs an S3 path as well — all of it without ever touching the public internet.
Layer 1's Secrets Manager interface endpoint is reused as-is (this layer's own copy of it is left
commented out in the source).

### 7. Security groups: a five-hop chain, with two rules injected backward into other layers

```
Public ALB SG → frontend SG (:3000) → internal ALB SG (:80) → backend SG (:5000) → database SG (:3306, layer 2)
```

Every arrow above is a **security-group-to-security-group** reference, never a CIDR block — meaning
the rule doesn't care what IP address a given Fargate task happens to have (a replaced task gets a
fresh one every time), only which security group it belongs to. Two of these rules aren't defined in
the layer that owns the resource they modify — they're written here, in layer 4, and reach backward:

```hcl
# Injected into LAYER 1's public ALB security group
resource "aws_security_group_rule" "alb_allow_outbound_to_frontend" {
  description = "RR: Retroactively injected by Layer 4 to allow ALB Egress"
  security_group_id        = data.aws_security_group.public_alb_sg.id   # layer 1's SG
  source_security_group_id = aws_security_group.rr_frontend.id           # this layer's SG
}

# Injected into LAYER 2's database security group
resource "aws_security_group_rule" "db_ingress_from_backend" {
  description = "RR: Retroactively injected by Layer 4 to allow Backend to access MySQL"
  security_group_id        = data.aws_security_group.database_sg.id     # layer 2's SG
  source_security_group_id = aws_security_group.rr_backend.id            # this layer's SG
}
```

This is the same "build an empty shell now, let the actual consumer inject its own rule later" idea
already introduced in `infrastructure/01-aws-vpc/README.md` (the ALB's egress) and
`infrastructure/02-aws-rds/README.md` (the database's ingress) — seen here from the consuming side,
completing both relationships. It's what lets five layers that are deployed independently, in strict
sequence, still end up with a fully-connected, least-privilege security group graph, without layer 1
or layer 2 ever needing to know layer 4 exists at the time they're first applied.

## Where this fits in the bigger picture

This layer is the ECS half of a deliberate two-platform comparison — the exact same container images
built in `apps/v1-frontend-nextjs` and `apps/v1-backend-flask` run here, unchanged, and later run
again on `infrastructure/05-aws-k8s`'s Kubernetes cluster. Per this project's sequential deploy order
(VPC → RDS → ECR → **ECS**, then destroy ECR and ECS, then Kubernetes), this layer is torn down once
its job is done, specifically so it isn't left running — and being billed — alongside the Kubernetes
stack it's being compared against. See `infrastructure/05-aws-k8s/README.md` for how that next
platform reuses this same shared public ALB the moment this layer is gone.
