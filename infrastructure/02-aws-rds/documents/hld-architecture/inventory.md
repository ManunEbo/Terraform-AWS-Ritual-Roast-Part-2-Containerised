# Layer 02-aws-rds — HLD inventory

Scope: RDS MySQL Multi-AZ, Secrets Manager secret + rotation Lambda,
Layer-2 SG shells.

## Approved decisions
- Draw the 3 Data subnets inside a cluster labelled
  `rr-dev-db-subnet-group (subnets from 01-aws-vpc)` — the subnets are
  external, only the subnet group is owned here.
- IAM role for the rotation Lambda shown in a grey dashed "IAM" box
  OUTSIDE the VPC (per the style map).
- Lambda layer shown OUTSIDE the VPC (artefact packaging, not a VPC
  resource).
- Do NOT draw a separate "external endpoints-SG" node; the Secrets Mgr
  interface endpoint's label and the Layer-2 SG-row box carry the
  Endpoints-SG relationship.

## Components

### IAM (outside VPC)
- `aws_iam_role.rr_lambda_secrets_role` — `modules/iam/iam-lambda.tf`.
  Attached managed policies:
  - `AWSLambdaVPCAccessExecutionRole` —
    `aws_iam_role_policy_attachment.rr_lambda_vpc_access`.
  - `AWSLambdaBasicExecutionRole` —
    `aws_iam_role_policy_attachment.rr_lambda_basic_execution`.
  - Custom `aws_iam_policy.rr_lambda_secrets_custom_policy`
    (secretsmanager:Get/Describe/Update/PutSecretValue/UpdateSecretVersionStage
    on `rr-dev-db-secret-*`, plus `cloudwatch:PutMetricData *`).

### Lambda packaging (outside VPC)
- `null_resource.rr_build_and_clean_layer` — `modules/lambda/layers.tf` —
  local-exec that `pip install`s `pymysql` and zips it.
- `aws_lambda_layer_version.rr_db_layer` — `modules/lambda/layers.tf` —
  layer `rr-dev-db-driver-layer`, runtime `python3.12 / python3.13`.

### Compute (inside VPC)
- `aws_lambda_function.rr_secret_rotation_function` —
  `modules/lambda/rotation.tf` — handler `index.lambda_handler`,
  runtime `python3.13`, mem 128MB, timeout 30s, VPC-attached in
  `data.aws_subnets.rr_db_subnets.ids` with `lambda_sg_id`.
  Depends on `time_sleep.wait_for_iam` (15s IAM eventual-consistency sleep).
- `data.archive_file.rr_rotation_zip` — zips `index.py` and `global-bundle.pem` (RDS CA bundle) at the zip root.

### Data (inside VPC)
- `aws_db_subnet_group.rr_db_subnet_group` — `modules/rds/rds.tf` —
  `rr-dev-db-subnet-group` built from the Layer-1 Data subnets.
- `aws_db_instance.rr_database` — `modules/rds/rds.tf` —
  `rr-dev-db`, `db_name=ritual_roast`, engine `mysql 8.4`,
  `db.t3.micro`, 20GB gp3, `multi_az=true`, `skip_final_snapshot=true`,
  `ignore_changes = [password]`. Credentials read from the SM secret
  via `data.aws_secretsmanager_secret_version.rr_latest_creds`.

### Secret
- `aws_secretsmanager_secret.rr_db_secret` — `modules/rds/secrets.tf` —
  `rr-dev-db-secret`, `recovery_window_in_days=0`.
- `aws_secretsmanager_secret_version.rr_db_skeleton` — initial
  user/pass/host=placeholder/port=3306 payload;
  `ignore_changes = [secret_string]`.
- `time_sleep.wait_for_secret` — 30s pause for AWS propagation.
- `data.aws_secretsmanager_secret_version.rr_latest_creds` — AWSCURRENT.
- `aws_secretsmanager_secret_version.rr_db_host_update` — rewrites
  secret with real RDS `address`; `ignore_changes = [secret_string]`.
- `aws_secretsmanager_secret_rotation.rr_db_rotation` — target
  `var.rotation_lambda_arn`, rotates every 7 days.
- `aws_lambda_permission.allow_secretsmanager_to_call_lambda` —
  `secretsmanager.amazonaws.com -> lambda:InvokeFunction`,
  `source_arn = rr_db_secret.arn`.

## Security groups
- `aws_security_group.rr_database` (name prefix `rr-dev-database-sg-`) —
  `modules/security_groups/sg-database.tf`.
  - Ingress 3306 from `rr_lambda` SG —
    `aws_security_group_rule.rr_db_ingress_from_lambda`.
  - (Backend ingress is injected later by Layers 4 and 5 — not here.)
- `aws_security_group.rr_lambda` (name `rr-dev-lambda-sg`) —
  `modules/security_groups/sg-lambda.tf`.
  - Egress 3306 to `rr_database` SG —
    `aws_security_group_rule.rr_lambda_egress_to_db`.
  - Egress 443 to Layer-1 `rr-dev-vpc-endpoints-sg` —
    `aws_security_group_rule.rr_lambda_egress_to_endpoints`.

## Cross-layer references (data sources)
- `data.aws_vpc.rr_vpc` — matched by `common_tags_vpc` + `tag:Name=rr-${env}-*`.
- `data.aws_subnets.rr_db_subnets` — tag filter `DataSubnet-*`.
- `data.aws_security_group.rr_endpoints_sg` — tag filter
  `rr-${env}-vpc-endpoints-sg` (in `modules/security_groups/data.tf`).
- `data.aws_caller_identity.current`, `data.aws_region.current`.

## Rules this layer injects into other layers
- INTO Layer-1 `rr-dev-vpc-endpoints-sg`:
  ingress 443 from `rr_lambda` SG —
  `aws_security_group_rule.endpoints_ingress_from_lambda`
  (in `modules/security_groups/sg-lambda.tf`).

## Findings (not fixed)
- Rotation Lambda runtime is `python3.13`.
