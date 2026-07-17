# Layer 2 — RDS, Secrets & Automatic Password Rotation

This layer builds the one thing every version of every backend in this project ultimately depends
on: a single shared MySQL database, plus the machinery that keeps its password secret and changes it
automatically on a schedule, without a human ever having to know what the current password is.

If you're new to this: think of a database as a locked filing cabinet, and this layer as building
both the cabinet *and* an automatic system that swaps the lock's key every week — quietly updating
every authorized person's copy of the key at the same moment, so nobody is ever left holding a key
that no longer works, and nobody outside the system ever needs to see the key at all.

## What this layer builds

| Module | Creates |
|---|---|
| `modules/rds` | The MySQL instance itself (Multi-AZ), its subnet group, and the two-stage Secrets Manager record that seeds its credentials. |
| `modules/lambda` | A small Python function that performs the actual password rotation, plus the dependency layer it needs to talk to MySQL. |
| `modules/iam` | The tightly-scoped role the Lambda function is allowed to run as. |
| `modules/security_groups` | Two security groups: one locked-down shell around the database, one for the Lambda that's allowed to reach it. |

## The database

```hcl
resource "aws_db_instance" "rr_database" {
  identifier        = "rr-${var.environment}-db"
  db_name           = "ritual_roast"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  multi_az          = true
  db_subnet_group_name   = aws_db_subnet_group.rr_db_subnet_group.name
  vpc_security_group_ids = [var.database_sg_id]
  username = jsondecode(data.aws_secretsmanager_secret_version.rr_latest_creds.secret_string)["username"]
  password = jsondecode(data.aws_secretsmanager_secret_version.rr_latest_creds.secret_string)["password"]
  skip_final_snapshot = true
  lifecycle { ignore_changes = [password] }
}
```

A `db.t3.micro` MySQL 8.0 instance on `gp3` storage — modest sizing, appropriate for a dev/portfolio
environment, but with one production-grade setting switched on deliberately: **`multi_az = true`**.
In plain terms, this doesn't just create one database server — it creates a second, synchronised
standby copy in a different Availability Zone, continuously kept up to date. If the primary ever
fails (hardware fault, an AWS maintenance patch, anything), AWS automatically promotes the standby
and redirects the database's DNS name to it, typically within 60–120 seconds, with no manual
intervention. It costs roughly double a single-AZ instance of the same size — a deliberate trade of
a modest amount of money for a real reduction in how badly a single hardware fault can hurt this
project. This exact behaviour — the 60–120 second window where the database is briefly unreachable
during a failover — is also the reason `apps/v2-backend-go`'s health checks are split into a shallow
liveness endpoint and a deep readiness endpoint; see that app's README for the full story of what
goes wrong if you get that split backwards.

Notice the username and password are read from a Secrets Manager **data source**, not hard-coded
variables — and `lifecycle { ignore_changes = [password] }` tells Terraform to stop caring about the
password after creation. Both details exist for the same reason: once the rotation Lambda (below)
starts changing the real password on its own schedule, Terraform must never "helpfully" reset it back
to whatever value it was originally created with the next time someone runs `terraform apply`.

## The two-stage secret: solving a chicken-and-egg problem

Secrets Manager needs to hold four things for any application to connect: username, password, **host**,
and port. But the RDS instance's hostname doesn't exist until *after* the instance itself is created —
and the instance needs a username/password to be created *with* in the first place. This layer solves
that ordering problem with two secret versions instead of one:

```hcl
# Stage 1 — exists before RDS does, host is a placeholder
resource "aws_secretsmanager_secret_version" "rr_db_skeleton" {
  secret_string = jsonencode({ username = var.db_username, password = var.db_password, host = "placeholder", port = 3306, dbname = "ritual_roast" })
  lifecycle { ignore_changes = [secret_string] }
}

# Stage 2 — runs only after the RDS instance exists, fills in the real host
resource "aws_secretsmanager_secret_version" "rr_db_host_update" {
  secret_string = jsonencode({ username = var.db_username, password = var.db_password, dbname = "ritual_roast", port = 3306, host = aws_db_instance.rr_database.address })
  depends_on = [aws_db_instance.rr_database]
  lifecycle { ignore_changes = [secret_string] }
}
```

The **skeleton** version gives the RDS instance something to be created with (a username and
password) before its own hostname is knowable. The **host-update** version then depends explicitly
on the RDS instance already existing, so it can read the instance's real `.address` and overwrite the
placeholder. Both versions set `ignore_changes = [secret_string]`, for the same reason as the
instance resource above: once the rotation Lambda starts writing real, rotated passwords into this
secret, Terraform must be blind to that drift rather than reverting it on the next apply. A
`data.aws_secretsmanager_secret_version` lookup (tracking the `AWSCURRENT` label Secrets Manager
maintains automatically) is what feeds the *current* credentials back into the RDS resource above,
so the whole thing self-consistently bootstraps in the right order on a first-ever `apply`.

## The rotation Lambda: AWS's four-step dance, actually implemented

```hcl
resource "aws_secretsmanager_secret_rotation" "rr_db_rotation" {
  secret_id           = aws_secretsmanager_secret.rr_db_secret.id
  rotation_lambda_arn = var.rotation_lambda_arn
  rotation_rules { automatically_after_days = 7 } # the standard rotation window is 30 days
  depends_on = [aws_secretsmanager_secret_version.rr_db_host_update]
}
```

Every 7 days (deliberately more aggressive than AWS's own commonly-cited 30-day default, chosen here
so the rotation cycle is actually observable within the lifetime of a dev/demo environment rather
than something you'd have to wait a month to see happen), Secrets Manager invokes a small Lambda
function that implements AWS's standard secret-rotation lifecycle end to end
(`modules/lambda/index.py`):

| Step | What it does |
|---|---|
| **createSecret** | Generates a new random 16-character password and stores it as a new, *pending* secret version — the live, current version is untouched so far. |
| **setSecret** | Logs into MySQL with the *current* (still-working) password and runs `ALTER USER ... IDENTIFIED BY '<new password>'` — this is the moment the database's actual password changes. |
| **testSecret** | Immediately logs in again, this time with the *new* password, to prove the change actually took effect before anything commits to it. |
| **finishSecret** | Only now does Secrets Manager relabel the new version as `AWSCURRENT` (and the old one stops being current) — so any application reading the secret from this point on gets the new password, and nothing was ever left in a half-changed state. |

This ordering is the entire point: the database is never without a working password (the old one
still works right up until `setSecret` succeeds), and the "official" secret never advances to the
new password until `testSecret` has already proven it actually works. A failure at any step simply
leaves the current, working credentials as they were — there's no window where every copy of the
password is simultaneously wrong.

The function needs a MySQL driver (`pymysql`) that isn't part of the standard Lambda Python runtime,
so it's supplied as a **Lambda layer**, built automatically at `terraform apply` time rather than
committed as a binary:

```hcl
resource "null_resource" "rr_build_and_clean_layer" {
  triggers = { dependency_version = "pymysql-v1.1" }
  provisioner "local-exec" {
    command = "pip install pymysql -t layers/python/ --no-cache-dir --upgrade && zip -rqy db_driver.zip python/"
  }
}
```

`source_code_hash = base64sha256(null_resource.rr_build_and_clean_layer.id)` is a small but
deliberate fix: Terraform normally wants to hash the actual zip file on disk to decide whether to
redeploy a Lambda layer, but that file doesn't exist yet during the *plan* phase (it's built by the
`local-exec` provisioner during *apply*) — hashing the triggering resource's ID instead avoids
Terraform reporting a confusing "inconsistent result after apply" error on every single run.

## IAM: scoped to one secret, not "Secrets Manager in general"

```hcl
Action = ["secretsmanager:GetSecretValue", "DescribeSecret", "UpdateSecret", "PutSecretValue", "UpdateSecretVersionStage"]
Resource = "arn:aws:secretsmanager:${region}:${account_id}:secret:rr-${var.environment}-db-secret-*"
```

The rotation Lambda's IAM policy grants exactly the five Secrets Manager actions the four-step
rotation lifecycle actually needs, and scopes every one of them to this one specific secret's ARN
pattern — not `"*"`. If this function were ever compromised, it could not read or modify any *other*
secret in the account, only this database's own credential record. The role additionally picks up
two AWS-managed policies (`AWSLambdaVPCAccessExecutionRole` so it can attach network interfaces
inside the VPC to actually reach RDS, and `AWSLambdaBasicExecutionRole` for CloudWatch logging) plus
one narrow custom grant for `cloudwatch:PutMetricData` — nothing here lets the function touch IAM,
S3, EC2, or any other AWS service.

## Security groups: zero-trust, populated across two layers

```hcl
resource "aws_security_group_rule" "rr_db_ingress_from_lambda" {
  from_port = 3306; to_port = 3306; protocol = "tcp"
  security_group_id        = aws_security_group.rr_database.id
  source_security_group_id = aws_security_group.rr_lambda.id
}

# This security group rule will be attached in ECS
# resource "aws_security_group_rule" "rr_db_ingress_from_backend" { ... }  (commented out here, deliberately)
```

The database's security group is annotated in the source as operating on a **"zero trust"** basis —
by default it allows nothing at all. This layer opens exactly one hole: port 3306 from the Lambda's
own security group, by security-group reference rather than an IP range, so only traffic that is
*actually coming from that specific Lambda* is ever let through de facto, regardless of what IP
address it happens to have on a given invocation. The matching rule that lets the *application*
backends reach the database is conspicuously commented out here — it isn't missing by accident, it's
intentionally left for whichever compute layer is actually running the backend to add for itself
(see `infrastructure/04-aws-ecs/README.md`'s security-group chapter, which injects exactly this rule
back into this layer's database security group once it knows its own backend security group's
identity). The same "shell now, inject later" pattern shows up in `infrastructure/01-aws-vpc`'s
endpoints security group, for the same reason: it lets independently-deployed layers cooperate
without any one of them needing to know about the others in advance.

The Lambda's own security group is described as **"a private operative"** — no inbound rules at all
(nothing ever initiates a connection *to* the rotation function), only two outbound rules: to the
database on 3306, and to the VPC's Secrets Manager interface endpoint on 443. That second rule
requires reaching back into `infrastructure/01-aws-vpc`'s endpoints security group and injecting an
ingress rule into *it* — the same cross-layer injection pattern, running in the opposite direction.

## Root wiring

```hcl
module "security_groups" { ... }
module "iam"              { ... }
module "lambda"           { role_arn = module.iam.lambda_role_arn, subnet_ids = data.aws_subnets... }
module "rds"               { rotation_lambda_arn = module.lambda.lambda_function_arn, ... }
```

The dependency chain is explicit and linear: security groups and IAM exist first, the Lambda is built
next (it needs both), and the RDS instance is created last, wired directly to that Lambda's ARN so
its `aws_secretsmanager_secret_rotation` resource can reference a Lambda that's guaranteed to already
exist. Layer 1's VPC ID and database-tier subnet IDs are pulled in via `data` source lookups by tag —
this layer never touches Layer 1's Terraform state directly, only its tagged, already-created
resources.

## Where this fits in the bigger picture

Both backend implementations in this project — `apps/v1-backend-flask` and `apps/v2-backend-go` —
connect to this exact database, using credentials they fetch from this exact secret at runtime, over
TLS (both bake in Amazon's RDS certificate bundle to verify the server rather than trusting it
blindly — see either app's README). Whether those backends are running on
`infrastructure/04-aws-ecs` or `infrastructure/05-aws-k8s`, they're reading from and writing to the
same rows in the same tables here, which is exactly what makes a live canary comparison between v1
and v2 meaningful: both versions are being judged against identical data, not separate copies of it.
