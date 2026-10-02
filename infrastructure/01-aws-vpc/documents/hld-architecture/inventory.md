# Layer 01-aws-vpc — HLD inventory

Scope: VPC foundation, subnets, routing, gateways, VPC endpoints,
shared public ALB, Layer-1 SG shells. Region `eu-west-2`.

## Approved decisions
- Draw all 3 AZs (eu-west-2a / 2b / 2c).
- NAT GW shown ONLY as a greyed dashed placeholder labelled
  "NAT GW — added by 05-aws-k8s". The real NAT lives in Layer 5.
- Keep the Secrets Manager icon (regional) because its Interface endpoint
  is owned by this layer.
- NO CloudWatch icon (nothing in this layer creates CW).
- NO Session Manager icon in this layer (Session Manager on Layer 5 only).
- SG chain row at bottom:
  - Single box `rr-dev-alb-sg — Inbound 80, 443 from 0.0.0.0/0`
    fed by a `0.0.0.0/0` box.
  - `rr-dev-vpc-endpoints-sg` standalone (no edge from ALB-SG);
    the relationship to the Secrets Mgr interface endpoint is carried
    in labels only.
- Tier header pills were tried (Public / Web / App / Data / K8s) and
  dropped — graphviz would not keep them aligned with their columns.
  Deviation from the reference example.
- `RouteTable` icon from mingrammer replaced with plain purple-outlined
  boxes because the icon ships with baked-in "172.16.x.x" text that
  contradicts this VPC's `10.16.0.0/16`.

## Components

### Network core
- `aws_vpc.rr_vpc` — `modules/vpc/vpc.tf` — CIDR `10.16.0.0/16`,
  DNS support + DNS hostnames on.
- `aws_subnet.public[0..2]` — `modules/vpc/subnets.tf` —
  `map_public_ip_on_launch = true`; CIDRs from `terraform.tfvars`:
  2a `10.16.0.0/20`, 2b `10.16.16.0/20`, 2c `10.16.32.0/20`.
- `aws_subnet.web[0..2]` — `modules/vpc/subnets.tf` —
  2a `10.16.64.0/20`, 2b `10.16.80.0/20`, 2c `10.16.96.0/20`.
- `aws_subnet.app[0..2]` — `modules/vpc/subnets.tf` —
  2a `10.16.128.0/20`, 2b `10.16.144.0/20`, 2c `10.16.160.0/20`.
- `aws_subnet.database[0..2]` — `modules/vpc/subnets.tf` —
  2a `10.16.192.0/20`, 2b `10.16.208.0/20`, 2c `10.16.224.0/20`.
- `aws_subnet.k8s[0..2]` — `modules/vpc/subnets.tf` —
  tagged `kubernetes.io/role/internal-elb=1`.
  2a `10.16.48.0/20`, 2b `10.16.112.0/20`, 2c `10.16.176.0/20`.

### Gateways / endpoints
- `aws_internet_gateway.main` — `modules/vpc/gateways.tf` — `dev-igw`.
- `aws_vpc_endpoint.s3` (Gateway) — `modules/vpc/gateways.tf` —
  attached to `aws_route_table.private` (verified; shared by web/app/db
  subnets).
- `aws_vpc_endpoint.rr_secretsmanager` (Interface) —
  `modules/endpoints/secrets_manager_endpoint.tf` — ENIs in
  App subnets 2a/2b/2c, `private_dns_enabled`,
  SG = `module.security_groups.endpoints_sg_id`.

### Routing
- `aws_route_table.public` + `aws_route.public_internet_access` —
  `modules/vpc/routing.tf` — default route `0.0.0.0/0 -> IGW`.
- `aws_route_table.private` — `modules/vpc/routing.tf` — no default
  route; associated with Web, App, Database subnets via
  `aws_route_table_association.{web,app,database}_assoc`.
- `aws_route_table.k8s_rt` — `modules/vpc/routing.tf` — no default route
  owned by this layer; Layer 5 injects `0.0.0.0/0 -> NAT GW`.
  Associated with the three K8s subnets via `aws_route_table_association.k8s_assoc`.

### Load balancer
- `aws_lb.rr_public` — `modules/load_balancers/alb-public.tf` —
  internet-facing, in `public_subnet_ids`, SG `module.security_groups.alb_sg_id`.
- `aws_lb_listener.rr_public_http` — port 80, default_action = fixed `404`.
  No commented-in forward target; Layer-4 and Layer-5 inject listener
  rules at their respective priorities (owned by those layers).

## Security groups
- `aws_security_group.rr_alb` (name `rr-dev-alb-sg`) —
  `modules/security_groups/sg-loadbalancer.tf`.
  - Ingress 80 from `0.0.0.0/0` — `aws_security_group_rule.rr_alb_allow_80_inbound`.
  - Ingress 443 from `0.0.0.0/0` — `aws_security_group_rule.alb_allow_443_inbound`.
- `aws_security_group.rr_endpoints_sg` (name prefix `rr-dev-vpc-endpoints-sg-`) —
  `modules/security_groups/sg-endpoints.tf`.
  - No rules defined in this layer. Ingress rules injected by L2, L4 and L5
    (see those layers).

## Cross-layer references
- None inbound. This layer is the base.

## Rules this layer injects into other layers
- None.

## Findings (not fixed)
- `rr-dev-alb-sg` allows 443 ingress but no port-443 listener exists on
  `aws_lb.rr_public`.
- `aws_route_table.private` has no `Tier` tag (only `Name` + common tags).
  Layer 4 later tries to look up private route tables filtered by
  `tag:Tier=app`, which fails to match any RT. See Layer 4 inventory.
- `aws_route_table.k8s_rt` has no S3 Gateway endpoint attached;
  K8s pod S3 traffic exits via the NAT GW added by Layer 5.
