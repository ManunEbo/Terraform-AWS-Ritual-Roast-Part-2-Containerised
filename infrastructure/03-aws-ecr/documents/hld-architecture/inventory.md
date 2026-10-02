# Layer 03-aws-ecr — HLD inventory

Scope: ECR repositories + lifecycle policies, GitHub Actions OIDC
federation, two CI push roles. No VPC resources.

## Approved decisions
- Flat account-level layout (no VPC frame).
- GitHub Actions drawn as an external reference node that federates
  into AWS via the OIDC provider.

## Components

### ECR
- `aws_ecr_repository.rr_frontend_repo` — `modules/ecr/ecr.tf` —
  `rr-dev-frontend`, `image_tag_mutability=IMMUTABLE`,
  `force_delete=true`, `scan_on_push=true`.
- `aws_ecr_repository.rr_backend_repo` — `modules/ecr/ecr.tf` —
  `rr-dev-backend`, same settings.
- `aws_ecr_lifecycle_policy.frontend_lifecycle` — keep last 5 images.
- `aws_ecr_lifecycle_policy.backend_lifecycle` — keep last 5 images.

### OIDC federation
- `data.tls_certificate.rr_github` — `modules/tls/tls.tf` — fetches
  GitHub's cert for its OIDC issuer URL.
- `aws_iam_openid_connect_provider.rr_github` — `modules/tls/tls.tf` —
  `url = https://token.actions.githubusercontent.com`,
  `client_id_list = [sts.amazonaws.com]`,
  thumbprint from the TLS data source.

### IAM — GitHub CI push roles
- `aws_iam_role.rr_github_frontend_role` — `modules/iam/iam_frontend.tf` —
  trust: `sts.AssumeRoleWithWebIdentity` from `rr_github` OIDC provider,
  conditions:
  - `token.actions.githubusercontent.com:aud = sts.amazonaws.com`
  - `token.actions.githubusercontent.com:sub LIKE repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:*`
- `aws_iam_role_policy.rr_github_frontend_policy` — allows
  `ecr:GetAuthorizationToken` on `*` plus
  `BatchCheckLayerAvailability | GetDownloadUrlForLayer | BatchGetImage |
  InitiateLayerUpload | UploadLayerPart | CompleteLayerUpload | PutImage`
  on `var.frontend_repo_arn` only.
- `aws_iam_role.rr_github_backend_role` — `modules/iam/iam_backend.tf` —
  same trust shape; policy limited to `var.backend_repo_arn`.
- `aws_iam_role_policy.rr_github_backend_policy` — mirror of frontend.

## Security groups
- None (no VPC resources in this layer).

## Cross-layer references
- None inbound. Downstream Layer 4 reads ECR images at runtime via its
  own `data` lookups and VPC endpoints.

## Rules this layer injects into other layers
- None.

## Findings
- None specific to this layer.
