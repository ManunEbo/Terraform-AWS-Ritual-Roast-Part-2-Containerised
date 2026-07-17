# Layer 1 — VPC, Networking & the Shared Front Door

This is the foundation. Every other layer in this project — the database, the container registry,
the ECS services, the Kubernetes cluster — lives *inside* the network this layer builds, and every
one of them reads this layer's outputs to find out where they're allowed to live.

If you've never worked with cloud networking before: a VPC (Virtual Private Cloud) is your own
private slice of AWS's network, walled off from every other customer's. Nothing in it is reachable
from the internet unless you deliberately open a door. This layer draws the walls, builds the rooms
(subnets), and installs exactly one public door (a load balancer) — everything built in later layers
moves into one of these rooms and, if it needs to be reachable from outside, asks the shared door to
forward traffic to it.

## What this layer builds

| Module | Creates |
|---|---|
| `modules/vpc` | The VPC itself, 15 subnets (five tiers across three availability zones), three route tables, and the internet gateway. |
| `modules/security_groups` | Two security group "shells" — one for the shared load balancer, one an empty base that later layers add rules into. |
| `modules/load_balancers` | The one public Application Load Balancer every later layer shares, with a deliberately minimal catch-all listener. |
| `modules/endpoints` | A private, in-VPC network path to AWS Secrets Manager, so credential lookups never have to leave the VPC. |

## The network layout

The VPC is a single `/16` (`10.16.0.0/16` — 65,536 addresses), carved into five tiers, each spread
across three Availability Zones (`eu-west-2a` / `2b` / `2c`) for resilience against a single AZ
failing:

| Tier | AZ 2a | AZ 2b | AZ 2c | What lives here |
|---|---|---|---|---|
| **Public** | `10.16.0.0/20` | `10.16.16.0/20` | `10.16.32.0/20` | The shared ALB only |
| **Web** | `10.16.64.0/20` | `10.16.80.0/20` | `10.16.96.0/20` | Frontend containers (layer 4, ECS) |
| **App** | `10.16.128.0/20` | `10.16.144.0/20` | `10.16.160.0/20` | Backend containers + Lambda (layers 2, 4) |
| **Database** | `10.16.192.0/20` | `10.16.208.0/20` | `10.16.224.0/20` | RDS (layer 2) |
| **K8s** | `10.16.48.0/20` | `10.16.112.0/20` | `10.16.176.0/20` | K3s EC2 nodes (layer 5) |

Each `/20` gives 4,096 addresses per subnet — generous headroom for a project this size, carved out
of the `/16` as contiguous, non-overlapping blocks so there's room to grow without re-plumbing
anything later. The K8s tier is tagged `kubernetes.io/role/internal-elb=1`, a label AWS's own
Kubernetes cloud-controller looks for so it can automatically discover the right subnets if an
internal Kubernetes-managed load balancer is ever created — a small detail, but one that has to be
right *before* Kubernetes exists, since it's a property of the subnet, not something Kubernetes can
add after the fact.

## Routing — and a deliberate absence

```hcl
resource "aws_route_table" "public" { ... }
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.main.id
}

resource "aws_route_table" "private" { ... }   # Web + App + Database tiers — no 0.0.0.0/0 route
resource "aws_route_table" "k8s_rt"  { ... }   # K8s tier — its own table, also no 0.0.0.0/0 route
```

Three route tables, not one: **public** (routed to the internet gateway — only the ALB lives here),
**private** (shared by the web, app, and database tiers), and a dedicated **k8s** table. Notice what's
*missing*: neither `private` nor `k8s_rt` has a `0.0.0.0/0` route to anywhere. **There is no NAT
gateway in this layer at all.** That's not an oversight — it's the direct consequence of a design
rule this project follows deliberately: a private subnet only gets a route to the general internet
if something in it genuinely needs to reach an arbitrary external address. Nothing in layers 1–4 does
— every AWS service they need (Secrets Manager, ECR, CloudWatch Logs, S3) is reachable through a
private VPC endpoint instead (see below, and `infrastructure/04-aws-ecs/README.md`), which is both
cheaper than a NAT gateway (no per-GB processing charge, no hourly charge) and more secure (traffic
never transits the public internet at all, even privately). The one exception is layer 5: K3s nodes
need to run `dnf update`, download Helm, and — critically — pull application images from
**ghcr.io**, an external registry with no AWS PrivateLink equivalent. That's genuine internet egress,
so `infrastructure/05-aws-k8s` provisions its *own* NAT gateway, scoped to just the K8s subnets, and
injects the missing route directly into this layer's `k8s_rt` table. NAT is paid for exactly once, by
the one layer that actually needs it — not kept running for four layers that never would.

The only gateway this layer *does* create is the internet gateway (for the public ALB) and a gateway
VPC endpoint for S3, attached to the `private` route table so the web/app/database tiers can reach S3
without any internet path at all:

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.rr_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}
```

A **Gateway** endpoint (as opposed to the Interface endpoint below) costs nothing beyond data
transfer — it works by adding a routing table entry rather than provisioning a network interface, so
there's no reason not to have it wherever S3 access is needed.

## The public ALB: a deliberately empty front door

```hcl
resource "aws_lb" "rr_public" {
  name               = "rr-${var.environment}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.public_alb_sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_listener" "rr_public_http" {
  load_balancer_arn = aws_lb.rr_public.arn
  port     = "80"
  protocol = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Service Not Found. Welcome to the Ritual Roast Gateway."
      status_code  = "404"
    }
  }
}
```

This is the single most important design decision in this layer: the ALB this creates has **no
target group and no routing rules of its own.** Its only listener is a port-80 HTTP listener whose
*default action* is a hard-coded 404. On its own, this ALB forwards nothing anywhere — it's a front
door with no rooms behind it yet.

That's deliberate, and the file itself shows the reasoning as commented-out code: an earlier version
of this file did define a target group and a forwarding listener directly here, scoped to ECS. It was
removed in favour of the current shape specifically **so the ALB could be shared** — rather than one
layer owning the ALB and every other layer having to work around that ownership, this layer provides
a neutral front door, and each layer that actually runs something (layer 4's ECS services, layer 5's
K3s frontend nodes) creates its *own* target group and attaches its *own* listener rule directly onto
this shared listener, at a distinct priority (see `infrastructure/04-aws-ecs/README.md` and
`infrastructure/05-aws-k8s/README.md`). Because layer 4 (ECS) and layer 5 (Kubernetes) are never
deployed at the same time in this project, their rules never actually compete — but the 404 default
action means that if *neither* is deployed (say, mid-migration between them), a request to the ALB
gets an honest "not found" instead of hanging or erroring in a way that's hard to diagnose.

The load balancer's own security group already permits inbound HTTPS on 443, even though today's only
listener is plain HTTP on 80:

```hcl
resource "aws_security_group_rule" "alb_allow_443_inbound" {
  type = "ingress"; from_port = 443; to_port = 443; protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rr_alb.id
}
```

The rule is annotated in the source as "a must-have for production" — it's a placeholder for adding
a TLS listener and an ACM certificate later, without needing a second change to the security group
when that happens.

## Security groups: two shells, populated by later layers

This layer creates exactly two security groups, and deliberately leaves one of them almost empty:

- **`rr_alb`** — the load balancer's SG, with the 80/443 inbound rules above. Its egress isn't
  restricted here at all (AWS's default allow-all-outbound applies), because at the point this layer
  is applied, the ALB doesn't yet know which target groups from which later layer it will need to
  reach — that permission is added by whichever layer is actually running (see
  `infrastructure/04-aws-ecs/README.md`'s security-group chapter for how ECS injects the specific
  "ALB → frontend, port 3000" rule back into *this* security group after the fact).
- **`rr_endpoints_sg`** — created with no rules at all beyond its name and a
  `create_before_destroy` lifecycle rule (so replacing it doesn't leave a dependent VPC endpoint
  briefly orphaned). It exists purely as a stable, named target other layers can attach ingress rules
  to later, without this layer needing to know in advance what will need to reach it.

This "create the shell now, let the consumer inject the specific rule later" pattern shows up
repeatedly across this project (see layer 2 and layer 4's security-group chapters) — it's what lets
five independently-deployed layers cooperate on a shared network without any one of them having to
be rewritten every time a new consumer is added.

## The Secrets Manager VPC endpoint

```hcl
resource "aws_vpc_endpoint" "rr_secretsmanager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [var.endpoints_sg_id]
  subnet_ids          = var.app_subnet_ids
  private_dns_enabled = true
}
```

Unlike the S3 endpoint above, Secrets Manager only offers an **Interface** endpoint — it works by
placing an actual elastic network interface (with a private IP) inside the App subnets, rather than
just a routing-table entry. `private_dns_enabled = true` is the detail that makes this transparent to
application code: it makes AWS's standard DNS name for Secrets Manager
(`secretsmanager.eu-west-2.amazonaws.com`) resolve *inside the VPC* to this private endpoint instead
of a public IP — so the boto3 / AWS SDK calls in `apps/v1-backend-flask` and
`apps/v2-backend-go` that fetch database credentials need zero code changes to use it; they just
call the standard AWS API and the network quietly keeps the traffic private.

## Root wiring and what's exported downstream

```hcl
module "vpc"             { source = "../../modules/vpc" ... }
module "security_groups" { source = "../../modules/security_groups"; vpc_id = module.vpc.vpc_id ... }
module "alb"              { source = "../../modules/load_balancers"; public_alb_sg_id = module.security_groups.alb_sg_id ... }
module "endpoints"        { source = "../../modules/endpoints"; endpoints_sg_id = module.security_groups.endpoints_sg_id ... }
```

The module order encodes the dependency graph directly: security groups exist before anything that
needs to reference them, and the endpoints module explicitly takes `endpoints_sg_id` as an input
specifically to force Terraform to build the security group before the endpoint that uses it (the
in-code comment calls this out as "the critical link").

What later layers actually consume, via Terraform outputs and (for a couple of values) plain data
source lookups by tag:

| Output | Consumed by |
|---|---|
| `vpc_id` | Every later layer |
| `public_subnet_ids` | Layer 4 (ALB target placement), Layer 5 (NAT gateway placement) |
| `database_subnet_ids` | Layer 2 (RDS subnet group) |
| `k8s_subnet_ids` | Layer 5 (K3s node placement) |
| `public_alb_sg_id` | Layers 4 and 5, to inject their own ingress rules |

`endpoints_sg_id` is deliberately **not** an output — later layers fetch it with a `data` source
lookup by tag instead, because (per the source comment) it doesn't need to be part of the formal
module contract. It's a small inconsistency worth being aware of if you're extending this layer:
most cross-layer values flow through outputs; this one flows through a tag-based lookup.

## `environments/prod/`

Only a `providers.tf` exists here — a stub pointing at a separate S3 state key
(`prod/state/terraform.tfstate`) with the same provider versions as `dev`. No production environment
has actually been built yet; the stub exists so a future prod build starts from the same module code
with different `environments/prod/*.tfvars`, rather than a copy-pasted fork of the dev configuration.

## Where this fits in the bigger picture

Every later layer depends on this one and none of them can be usefully applied without it. The
sequential deploy order that runs through this whole project — VPC, then RDS, then ECR, then ECS,
then (after destroying ECR/ECS) Kubernetes — exists specifically because layers 2 onward all read
this layer's subnet IDs, VPC ID, and security groups as inputs. See the root project documentation
for the full five-layer sequence, and `infrastructure/04-aws-ecs/README.md` /
`infrastructure/05-aws-k8s/README.md` for how each of them attaches its own listener rule onto the
one ALB this layer creates.
