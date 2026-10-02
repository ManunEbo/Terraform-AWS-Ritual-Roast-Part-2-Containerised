# Layer 05-aws-k8s — HLD inventory

Scope: K3s HA control plane + two worker ASGs on EC2 (self-managed),
Calico CNI, Istio ingress target group bound to the Layer-1 public ALB
listener, internal NLB for the K3s API, NAT GW, Secrets Manager secrets
for GitOps + Grafana + the K3s join token, IAM instance profiles.

## Approved decisions
- Draw the single NAT GW in Public subnet 2a (as created by this layer).
- Draw a Session Manager icon on this layer (CP + workers get
  `AmazonSSMManagedInstanceCore`).
- SG chain at the bottom shows only the user-request path:
  `0.0.0.0/0 → L1 ALB-SG :80 → worker-frontend-sg :30080`,
  then overlay/mesh traffic in-cluster `→ worker-backend-sg → L2 database-sg :3306`
  (RDS ingress-from-backend drawn as "injected into L2").
- All Calico / Istio / Typha / Kubelet / IPIP / metrics / xDS ports go
  into a side legend box, not into the main SG chain.
- Draw the internal NLB (6443) and public ALB-attached frontend TG
  (:30080) as two distinct LB objects — they serve different purposes
  (K3s API HA vs app ingress).

## Components

### Network
- `aws_eip.rr_k8s_nat_eip` — `modules/network_k8s/nat-gateway.tf`.
- `aws_nat_gateway.rr_k8s_nat` — in `var.public_subnet_id`
  (`PublicSubnet-01-2a` via `data.aws_subnet.rr_public_subnet_1`).
- `aws_route.rr_inject_k8s_internet_access` — INJECTED into Layer-1
  `k8s_rt`: `0.0.0.0/0 → aws_nat_gateway.rr_k8s_nat`.
- `data.aws_route_table.k8s_rt` — Layer-1 route table matched by
  tag `Name=rr-${env}-${vpc_name}-k8s-private-rt`.

### Compute (all AL2023, `t3.medium`)
- `data.aws_ami.rr_al2023` — `modules/compute_k8s/data.tf` —
  most-recent `al2023-ami-2023.*-x86_64` from Amazon.
- `aws_launch_template.rr_k3s_cp` + `aws_autoscaling_group.rr_k3s_cp_asg` —
  `modules/compute_k8s/controlplane.tf` — desired/min/max 3, in
  `k8s_private_subnets`, SG `control_plane_sg_id`, instance profile
  `iam_profile_control_plane`, IMDSv2 required with `hop_limit=2`,
  user_data = `user_data_cp.sh` (nlb DNS + DB_SECRET_ARN injected).
- `aws_autoscaling_attachment.rr_k3s_cp_asg_attach` — attaches CP ASG
  to the NLB TG.
- `aws_launch_template.rr_k3s_worker_frontend` +
  `aws_autoscaling_group.rr_k3s_worker_frontend_asg` —
  `modules/compute_k8s/worker-frontend.tf` — desired 1 min 1 max 4,
  user_data = `user_data_worker_frontend.sh` (node_role=frontend).
- `aws_launch_template.rr_k3s_worker_backend` +
  `aws_autoscaling_group.rr_k3s_worker_backend_asg` —
  `modules/compute_k8s/worker-backend.tf` — desired 1 min 1 max 4,
  `instance_refresh` strategy Rolling (min_healthy=50%), node_role=backend.

### Load balancers
- `aws_lb.rr_k3s_cp_nlb` — `modules/compute_k8s/controlplane.tf` —
  internal NLB in `k8s_private_subnets`, SG `nlb_sg_id`.
- `aws_lb_target_group.rr_k3s_cp_tg` — port 6443 TCP, target_type `instance`,
  TCP health check port 6443.
- `aws_lb_listener.rr_k3s_cp_listener` — 6443 TCP → `rr_k3s_cp_tg`.
- `aws_lb_target_group.rr_k8s_frontend_tg` —
  `modules/load-balancers_k8s/alb-ingress-wiring.tf` —
  `rr-dev-k8s-frontend-istio-tg`, port 30080 HTTP, target_type `instance`,
  health check `/` port 30080.
- `aws_autoscaling_attachment.rr_k8s_frontend_asg_attach` — attaches the
  frontend worker ASG to the Istio ingress TG.
- `aws_lb_listener_rule.rr_k8s_absolute_cutover` — INJECTED into Layer-1
  public ALB listener, priority 10, `/* → rr_k8s_frontend_tg`.

### Secrets (Secrets Manager)
- `aws_secretsmanager_secret.rr_github_pat` + version —
  `rr-dev-argocd-github-token` (`modules/security_k8s/github_pat_secret.tf`).
- `aws_secretsmanager_secret.rr_grafana_token` + version —
  `rr-dev-grafana-cloud-token`
  (`modules/security_k8s/grafana_token_secret.tf`).
- `aws_secretsmanager_secret.rr_grafana_remote_write_url` + version —
  `rr-dev-grafana-remote-write-url`.
- `aws_secretsmanager_secret.rr_grafana_instance_id` + version —
  `rr-dev-grafana-instance-id`.
- `random_password.k3s_join_token` + `aws_secretsmanager_secret.rr_k3s_join_token`
  + version — `rr-dev-k3s-join-token`
  (`modules/security_k8s/cluster_join_token_secret.tf`).

### IAM (outside VPC)
- `aws_iam_role.rr_k3s_control_plane_role` +
  `AmazonSSMManagedInstanceCore` +
  `aws_iam_policy.rr_cp_custom_policy`
  (`ec2:DescribeInstances *`; `secretsmanager:GetSecretValue|DescribeSecret`
  on `rr-${env}-argocd-github-token-*`, `rr-${env}-k3s-join-token-*`,
  `rr-${env}-grafana-cloud-token-*`, `-grafana-remote-write-url-*`,
  `-grafana-instance-id-*`) +
  `aws_iam_instance_profile.rr_k3s_cp_profile`.
- `aws_iam_role.rr_k3s_worker_frontend_role` +
  `AmazonSSMManagedInstanceCore` +
  `aws_iam_policy.rr_worker_frontend_custom_policy`
  (secret `rr-${env}-k3s-join-token-*`) +
  `aws_iam_instance_profile.rr_k3s_worker_frontend_profile`.
- `aws_iam_role.rr_k3s_worker_backend_role` +
  `AmazonSSMManagedInstanceCore` +
  `aws_iam_policy.rr_worker_backend_custom_policy`
  (secrets `rr-${env}-db-secret-*` and `rr-${env}-k3s-join-token-*`) +
  `aws_iam_instance_profile.rr_k3s_worker_backend_profile`.

## Security groups (user-path members)
- `aws_security_group.rr_k8s_control_plane_sg` —
  `modules/security_k8s/controlplane-sg.tf`.
  - Ingress 6443/tcp from worker-frontend, worker-backend, nlb SGs.
  - Self-ingress all protos (etcd/mesh).
  - Egress all VPC CIDR + 80/tcp 443/tcp to `0.0.0.0/0`.
- `aws_security_group.rr_k8s_worker_frontend_sg` —
  `modules/security_k8s/worker-frontend-sg.tf`.
  - Ingress 30080/tcp from Layer-1 ALB SG —
    `aws_security_group_rule.rr_frontend_ingress_http_alb` (user path hop).
  - Ingress 10250/tcp (kubelet) from CP SG.
  - Ingress 15017/tcp (Istio webhook) from CP SG.
  - Self-ingress all protos.
  - Egress all VPC CIDR + 80/443 to `0.0.0.0/0`.
- `aws_security_group.rr_k8s_worker_backend_sg` —
  `modules/security_k8s/worker-backend-sg.tf`.
  - Ingress all protos from worker-frontend SG —
    `aws_security_group_rule.rr_backend_ingress_from_frontend`
    (frontend→backend overlay path).
  - Ingress 10250/tcp from CP SG; Ingress 15017/tcp from CP SG.
  - Self-ingress all protos.
  - Egress all VPC CIDR + 80/443 to `0.0.0.0/0`.
- `aws_security_group.rr_k8s_nlb_sg` —
  `modules/security_k8s/nlb-sg.tf`.
  - Ingress 6443/tcp from worker-frontend and worker-backend SGs.
  - Egress 6443/tcp to control-plane SG.

## Security groups (control/mesh — side legend)
Grouped by concern; all rules in `modules/security_k8s/*-sg.tf`.
- Calico BGP (TCP/179): CP↔frontend, CP↔backend —
  `rr_cp_ingress_calico_bgp_frontend|_backend`,
  `rr_frontend_ingress_calico_bgp_cp|_backend`,
  `rr_backend_ingress_calico_bgp_cp`.
- Calico VXLAN (UDP/4789): same pattern.
- Calico Typha (TCP/5473): CP from workers; workers from CP; frontend from backend.
- Calico IPIP fallback (proto 4): CP↔workers.
- Istio injection webhook (TCP/15017): CP→workers.
- Istiod xDS discovery (TCP/15012): workers→CP.
- Metrics server (TCP/4443): CP→workers.

## Cross-layer references (data sources)
- `data.aws_vpc.rr_vpc`, `data.aws_subnets.rr_k8s_subnets`,
  `data.aws_subnet.rr_public_subnet_1`.
- `data.aws_internet_gateway.rr_igw`.
- `data.aws_security_group.rr_alb_sg` — Layer-1 ALB SG.
- `data.aws_security_group.rr_rds_sg` — Layer-2 database SG.
- `data.aws_security_group.rr_endpoints_sg` — Layer-1 endpoints SG.
- `data.aws_lb.gateway_alb` + `data.aws_lb_listener.gateway_http_listener`.
- `data.aws_secretsmanager_secret.rr_db_secret` — Layer-2 secret
  (injected into the CP user_data template).

## Rules this layer injects into other layers
- INTO Layer-1 `k8s-private-rt`:
  `aws_route.rr_inject_k8s_internet_access` — `0.0.0.0/0 → NAT GW`.
- INTO Layer-1 ALB SG:
  egress 30080/tcp to worker-frontend SG —
  `aws_security_group_rule.rr_alb_egress_to_frontend_http`.
- INTO Layer-1 `rr-dev-vpc-endpoints-sg`:
  ingress 443/tcp from each of CP SG, worker-frontend SG,
  worker-backend SG —
  `rr_endpoints_ingress_from_cp`,
  `rr_endpoints_ingress_from_wkr_frontend`,
  `rr_endpoints_ingress_from_wkr_backend`.
- INTO Layer-2 `database_sg`:
  ingress 3306/tcp from worker-backend SG —
  `aws_security_group_rule.rr_rds_ingress_from_backend`.
- INTO Layer-1 public ALB listener:
  `aws_lb_listener_rule.rr_k8s_absolute_cutover`, priority 10,
  `/* → rr_k8s_frontend_tg`.

## Findings
- None specific to this layer. (For the Istio/Calico/K3s runtime
  bugs resolved in CLAUDE.md: those are code states already fixed and
  live-verified; they are not open findings against the HLD.)
