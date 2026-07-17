# Layer 3 — Container Registry & Passwordless CI

This layer builds the private container registry that holds the built application images, plus the
identity plumbing that lets GitHub Actions push new images into it — **without ever storing an AWS
password or access key inside GitHub**. It exists specifically for the ECS deployment path
(`infrastructure/04-aws-ecs`); once this project moves into its Kubernetes phase, images are pulled
from GitHub Container Registry (`ghcr.io`) instead, and this layer is deliberately destroyed
alongside layer 4 to stop paying for infrastructure nothing is using. See "Where this fits" at the
bottom for that full lifecycle.

If you haven't encountered a container registry before: it's the same idea as a package registry
like the npm or PyPI you might already know, except it stores whole application images (code,
runtime, and dependencies bundled together) rather than individual libraries. `docker push` uploads
an image to it; the compute layer that runs the app (`docker pull` / ECS's equivalent) downloads from
it.

## What this layer builds

| Module | Creates |
|---|---|
| `modules/ecr` | Two container image repositories — one for the frontend, one for the backend — each with vulnerability scanning and an automatic cleanup policy. |
| `modules/tls` | The trust relationship that lets AWS verify a GitHub Actions token is genuinely from GitHub. |
| `modules/iam` | Two IAM roles, one per repository, that GitHub Actions assumes temporarily to push images — never a stored credential. |

## The registry: two repositories, each self-cleaning

```hcl
resource "aws_ecr_repository" "rr_frontend_repo" {
  name                 = "rr-${var.environment}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}
```

- **`image_tag_mutability = "MUTABLE"`** allows a tag like `:latest` to be re-pushed and point at a
  new image over time — needed because the CI pipeline (`.github/workflows/deploy-ecs.yml.disabled`)
  pushes both a fixed `:latest` tag and an immutable `:<commit-sha>` tag on every build; only the
  `:latest` tag actually needs to move.
- **`scan_on_push = true`** triggers AWS's built-in vulnerability scan (via Trivy under the hood)
  automatically on every image that lands in the repository, with no separate CI step required to
  request it.
- **`force_delete = true`** is a deliberate cost/lifecycle decision, not a default left unconsidered:
  it allows `terraform destroy` to remove these repositories *and every image inside them*
  immediately, without first requiring them to be emptied by hand. That's exactly what's wanted for
  a repository that's designed to be destroyed and recreated as part of the ECS↔Kubernetes cost-saving
  cycle described below — in a permanent production registry you would leave this `false` as a
  guard-rail against an accidental destroy.

Each repository also carries a lifecycle policy:

```hcl
resource "aws_ecr_lifecycle_policy" "frontend_lifecycle" {
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action    = { type = "expire" }
    }]
  })
}
```

Only the five most recent images (tagged or not) are ever kept; anything older is expired
automatically. That keeps storage cost flat over time regardless of how many times CI runs, at the
cost of not being able to roll back further than five builds — a reasonable trade for a dev
environment where the git history (and the ability to rebuild any older commit) is the real source
of truth, not the registry itself.

## OIDC: proving "this is really GitHub Actions" without a password

```hcl
data "tls_certificate" "rr_github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "rr_github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.rr_github.certificates[0].sha1_fingerprint]
}
```

This is the single most important security decision in this layer, and it's worth explaining plainly
because it's easy to under-appreciate: **there is no AWS access key or secret key stored in this
project's GitHub repository at all.** The conventional (weaker) alternative would be to generate a
long-lived AWS IAM user access key, paste it into a GitHub Actions secret, and let every workflow run
use it forever until someone remembers to rotate it. Instead, this sets up **OIDC federation**:
GitHub's own token-issuing endpoint is registered with AWS IAM as a trusted identity provider,
verified cryptographically via a certificate thumbprint (fetched live via a `data` source, so if
GitHub ever rotates their signing certificate, the next `terraform apply` automatically picks up the
new thumbprint with no manual maintenance). From that point on, a GitHub Actions workflow run can ask
GitHub for a short-lived identity token and hand it directly to AWS in exchange for temporary
credentials — typically valid for about an hour — that expire on their own even if nothing goes
wrong. If a workflow log or a compromised dependency ever leaked one of these tokens, the exposure
window is measured in minutes, not "until someone notices and rotates a key manually."

## Two roles, each locked to exactly one repository

```hcl
resource "aws_iam_role" "rr_github_backend_role" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_provider_arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:*" }
      }
    }]
  })
}
```

Trusting "any valid GitHub token" would still be far too broad — the `Condition` block narrows that
down twice: `aud` (audience) must equal `sts.amazonaws.com`, and `sub` (subject) must match **this
specific GitHub repository**, wildcarded only on branch/tag. A token minted by a workflow in some
other GitHub repository, even one the same organisation owns, cannot assume this role at all.

Each role's *permissions* policy is scoped just as tightly, this time to a single ECR repository ARN:

```hcl
{
  Sid = "AllowPushToBackendRepoOnly"
  Action = ["ecr:BatchCheckLayerAvailability", "GetDownloadUrlForLayer", "BatchGetImage",
            "InitiateLayerUpload", "UploadLayerPart", "CompleteLayerUpload", "PutImage"]
  Resource = var.backend_repo_arn
}
```

The **backend** role's policy names only the backend repository's ARN; a mirror-image **frontend**
role names only the frontend repository's ARN. Neither role can push to the other's repository, and
neither can delete an image at all — every action here is additive (upload layers, push a tag), never
`DeleteImage` or `BatchDeleteImage`. If the frontend build workflow were ever compromised, the
attacker gains the ability to push a bad frontend image — not to touch the backend registry, and not
to erase anything already there. That containment is worth exactly as much as the blast radius it
prevents: one compromised workflow, one affected repository, not two.

## Where this fits in the bigger picture

This layer only matters while `infrastructure/04-aws-ecs` is deployed — ECS task definitions pull
images directly from these two repositories by URL. Per this project's deploy sequence (VPC → RDS →
ECR → ECS, then **destroy ECR and ECS**, then Kubernetes), this layer is torn down once the project
moves to demonstrating the Kubernetes/Istio canary strategies, specifically so two registries and
their surrounding IAM aren't left running (and being paid for) unused. `force_delete = true` above is
what makes that teardown clean — `terraform destroy` doesn't need a separate "empty the repository
first" step.

The Kubernetes phase (`infrastructure/05-aws-k8s`) does **not** use this ECR at all: it pulls both
app versions' images from `ghcr.io` (GitHub Container Registry) instead, authenticated with a GitHub
Personal Access Token rather than this layer's OIDC roles — a different registry, a different
push/pull mechanism, and a completely independent workflow
(`.github/workflows/deploy-ghcr-k8s.yml`) from the one this layer's IAM roles serve
(`.github/workflows/deploy-ecs.yml.disabled`, renamed `.disabled` for exactly this reason — its OIDC
role no longer exists once this layer is destroyed, so leaving it enabled would red-X on every push
for no reason). Re-enable that workflow only once layers 3 and 4 are redeployed.
