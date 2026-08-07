# Layer 3 - Elastic Container Registry

In this layer, we set up the GitHub Personal Access Token (PAT) authentication and deploy AWS Elastic Container Registry (ECR) to house the frontend and backend container images for **Elastic Container Service (ECS)**. This is the only Layer that doesn't pull state from its predecessors—it does not require the VPC, subnets, Security Groups, RDS, or Lambda resources. Its sole purpose is to provision the container registry to house Docker images on AWS.

## Dev Environment

Structurally, there is nothing new in this environment that we haven't seen in earlier layers.

## Setting up the GitHub PAT

Instructions to create the GitHub PAT are in [Setting-up-GitHub-PAT-Manually.txt](https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised/blob/main/infrastructure/03-aws-ecr/documents/Setting-up-GitHub-PAT-Manually.txt). Once configured, we are ready to create the ECR repositories and push our workflows to GitHub.

---

# Modules

There are three modules in this Layer. Let's look at each one in detail:

## tls

This module provides the GitHub authentication setup used to authenticate with AWS via **OpenID Connect (OIDC)**. OIDC allows AWS to trust identity claims issued by GitHub without sharing long-lived secret keys or passwords, using the OpenID Connect protocol as a standardized federated trust framework.

**Core Concepts**

Key OIDC concepts:

1. **Identity Provider (IdP):** GitHub authenticates entities (users, workloads, or CI pipelines) and issues a signed JSON Web Token (JWT) containing metadata about the entity, issue time, expiration, and audience.
2. **Relying Party (RP):** AWS relies on the IdP for identity validation. It verifies incoming tokens cryptographically against the IdP's public keys, ensuring the token is unexpired and intended for AWS.
3. **Temporary Credentials:** If the token validates, AWS grants temporary access credentials via STS rather than using static, long-lived access keys.

**Why This Matters**

Applying this to our stack:

1. GitHub acts as the IdP, asserting which repository, branch, and workflow is running.
2. AWS acts as the Relying Party, trusting tokens signed by GitHub's OIDC issuer via the `aws_iam_openid_connect_provider` resource.
3. On every workflow run, GitHub creates a fresh JWT valid only for that run. The workflow presents this token to AWS STS via `sts:AssumeRoleWithWebIdentity`. AWS verifies the signature and condition checks in the IAM role's trust policy before returning short-lived credentials (typically valid for 1 hour).

**Advantages Over Static Keys**

1. **No Long-Lived Secrets:** No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` stored in GitHub Secrets that could leak or be exfiltrated.
2. **Automatic Expiration:** Temporary credentials expire quickly, reducing the window of impact if intercepted.
3. **Fine-Grained Declarative Trust:** Trust policies scope access strictly down to specific repositories, branches, or environments.

### tls.tf

```hcl
data "tls_certificate" "rr_github" {
  url = "https://token.actions.githubusercontent.com"
}
```

This data source performs a live TLS handshake against GitHub's OIDC token issuer endpoint and retrieves the certificate chain. Fetching this dynamically ensures that when GitHub rotates its TLS certificates, `terraform apply` automatically grabs the newest certificate rather than relying on a hardcoded string.

```hcl
resource "aws_iam_openid_connect_provider" "rr_github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.rr_github.certificates[0].sha1_fingerprint]
}
```

This registers GitHub as a trusted external IdP inside AWS IAM:

1. `url = "https://token.actions.githubusercontent.com"` - The OIDC issuer URL. Matches the `iss` (issuer) claim in GitHub's JWTs.
2. `client_id_list = ["sts.amazonaws.com"]` - The audience (`aud` claim) expected by AWS STS.
3. `thumbprint_list = [...]` - Extracts the SHA-1 fingerprint of GitHub's server certificate. _(Note: AWS IAM uses an internal root CA library for GitHub OIDC verification, but Terraform requires this argument for schema compatibility)._

### outputs.tf

```hcl
output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.rr_github.arn
}
```

Outputs the OIDC Provider ARN to be consumed by the `iam` module for role trust relationships.

---

## ecr

This module creates Amazon Elastic Container Registry (ECR) repositories for our frontend and backend Docker images. Once created, GitHub Actions workflows can push built images to these repositories for deployment in Layer 4 (ECS).

### ecr.tf

```hcl
resource "aws_ecr_repository" "rr_frontend_repo" {
  name                 = "rr-${var.environment}-frontend"
  image_tag_mutability = "IMMUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.common_tags, {
    Name = "rr-${var.environment}-frontend-repo"
  })
}
```

Configuration details:

1. `name = "rr-${var.environment}-frontend"` - Repository name, forming part of the full URI: `<account_id>.dkr.ecr.<region>.amazonaws.com/rr-dev-frontend`.
2. `image_tag_mutability = "IMMUTABLE"` - Prevents image tags (e.g., `v1.0.0`) from being overwritten. Immutability ensures deployments remain deterministic and tag-based rollbacks point to exact, unmodified images.
3. `force_delete = true` - Allows Terraform to delete non-empty repositories during `terraform destroy` without requiring manual image purging beforehand.
4. `image_scanning_configuration { scan_on_push = true }` - Automatically scans pushed images for Common Vulnerabilities and Exposures (CVEs).
5. `tags` - Merges standard resource tags.

**ECR Lifecycle Policy**

To control storage costs, lifecycle policies automatically clean up older images:

```hcl
resource "aws_ecr_lifecycle_policy" "frontend_lifecycle" {
  repository = aws_ecr_repository.rr_frontend_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

Key attributes:

1. `repository`: Links the policy to the ECR repository.
2. `rulePriority = 1`: Execution order for policy rules.
3. `selection`: Defines evaluation criteria:
   - `tagStatus = "any"`: Evaluates both tagged and untagged images.
   - `countType = "imageCountMoreThan"`: Retains a fixed count of images.
   - `countNumber = 5`: Retains the 5 most recent images and expires older ones.
4. `action = { type = "expire" }`: Deletes images matching the criteria.

### outputs.tf

Exposes repository ARNs needed for IAM scoping:

1. `output "frontend_repo_arn" {}`
2. `output "backend_repo_arn" {}`

---

## iam

Configures IAM roles and permissions allowing GitHub Actions runners to authenticate and push images to ECR.

### JWT Token Payload Example

When a workflow runs, GitHub issues a signed JWT payload structured like this:

```json
{
	"iss": "https://token.actions.githubusercontent.com",
	"aud": "sts.amazonaws.com",
	"sub": "repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:ref:refs/heads/main",
	"repository": "ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised",
	"repository_owner": "ManunEbo",
	"actor": "ManunEbo",
	"workflow": "Deploy Frontend",
	"run_id": "1234567890",
	"event_name": "push",
	"ref": "refs/heads/main",
	"sha": "a1b2c3d4e5f6789012345678901234567890abcd",
	"iat": 1775030400,
	"exp": 1775031000
}
```

Claims evaluated by AWS:

1. `"iss"`: Issuer URL. AWS validates this against the registered OIDC provider and verifies the signature via GitHub's public key endpoint (`/.well-known/jwks`).
2. `"aud"`: Intended Audience. Verified against `sts.amazonaws.com` in the role trust policy.
3. `"sub"`: Subject context (repository, ref, or environment). Evaluated via `StringLike` wildcards in the trust policy.
4. `"iat"` & `"exp"`: Timestamps ensuring token validity and preventing expired token usage.

### iam_frontend.tf

**aws_iam_role**

```hcl
resource "aws_iam_role" "rr_github_frontend_role" {
  name = "rr-${var.environment}-github-frontend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:*"
        }
      }
    }]
  })
}
```

Key components:

1. `assume_role_policy`: The trust policy defining who can assume the role.
2. `Action = "sts:AssumeRoleWithWebIdentity"`: Allows exchanging a federated OIDC JWT for temporary AWS credentials.
3. `Principal = { Federated = var.oidc_provider_arn }`: Trusts the GitHub OIDC provider.
4. `Condition`:
   - `"token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"`: Enforces exact audience matching to prevent token replay attacks across different services.
   - `"token.actions.githubusercontent.com:sub"`: Restricts role assumption strictly to workflows originating from `ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised`.

**aws_iam_role_policy**

This inline policy defines what actions the GitHub runner can execute once assumed:

```hcl
resource "aws_iam_role_policy" "rr_github_frontend_policy" {
  name = "rr-${var.environment}-github-frontend-policy"
  role = aws_iam_role.rr_github_frontend_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowECRLogin",
        Effect   = "Allow",
        Action   = "ecr:GetAuthorizationToken",
        Resource = "*"
      },
      {
        Sid    = "AllowPushToFrontendRepoOnly",
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ],
        Resource = var.frontend_repo_arn
      }
    ]
  })
}
```

Detailed policy rules:

- **Statement 1 (`AllowECRLogin`):** Grants `ecr:GetAuthorizationToken` on `Resource = "*"` to fetch registry login credentials via the AWS CLI. AWS requires `*` for this API call because authentication tokens are account-level.
- **Statement 2 (`AllowPushToFrontendRepoOnly`):** Grants permission to push Docker images, scoped strictly to `var.frontend_repo_arn` following the Principle of Least Privilege:
  1. **Phase 1 (Pre-check):** `BatchCheckLayerAvailability`, `GetDownloadUrlForLayer`, and `BatchGetImage` verify existing image layers to optimize build caches and prevent duplicate uploads.
  2. **Phase 2 (Layer Upload):** `InitiateLayerUpload`, `UploadLayerPart`, and `CompleteLayerUpload` stream image layer byte chunks to ECR.
  3. **Phase 3 (Publishing):** `PutImage` uploads the final image manifest and links the associated tag or digest.

### outputs.tf

```hcl
output "frontend_github_role_arn" {
  value = aws_iam_role.rr_github_frontend_role.arn
}

output "backend_github_role_arn" {
  value = aws_iam_role.rr_github_backend_role.arn
}
```

These outputs export the IAM Role ARNs for use in GitHub Actions pipeline secrets.

---

## Instructions

Step-by-step deployment guide for Layer 3:

1. Retrieve the S3 backend bucket name created in Layer 1.
2. Open `03-aws-ecr/environments/dev/providers.tf` and update the `bucket` field with your bucket name.
3. Verify the AWS region in `providers.tf` matches your target region (e.g., `eu-west-2`).
4. Update `03-aws-ecr/environments/dev/shared_locals.tf` tags and variables as required.
5. Change directory to the environment folder:
   ```bash
   cd infrastructure/03-aws-ecr/environments/dev
   ```
6. Set a shell alias for convenience:
   ```bash
   alias tf=terraform
   ```
7. Generate and export your GitHub PAT as detailed in [Setting-up-GitHub-PAT-Manually.txt](https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised/blob/main/infrastructure/03-aws-ecr/documents/Setting-up-GitHub-PAT-Manually.txt).
8. Initialize Terraform:
   ```bash
   tf init
   ```
9. Review execution plan:
   ```bash
   tf plan
   ```
10. Apply the configuration:
    ```bash
    tf apply
    ```
11. Proceed to Layer 4 (ECS Deployment).
