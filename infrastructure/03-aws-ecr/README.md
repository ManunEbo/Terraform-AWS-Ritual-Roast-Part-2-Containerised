# Layer 3 - Elastic Container Registry

In this layer we create the GitHub Personal Access Token (PAT) and deploy ECR to house the frontend and backend images for **Elastic Container Service (ECS)**. This is the only Layer that doesn't pull anything from it's predecessors. It doesn't need the VPC, subnets, Security groups, RDS, Lambda etc. Its sole purpose is to provision the registry to house docker container images on AWS.

## Dev environnment

Structurally, there's nothing we haven't seen before in this environment.

## Setting up the GitHub PAT

The instructions to create the GitHub PAT are in [Setting-up-GitHub-PAT-Manually.txt](https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised/blob/main/infrastructure/03-aws-ecr/documents/Setting-up-GitHub-PAT-Manually.txt). Once you have that setup we are ready to create the ECR and to push the workflows to GitHub.

# Modules

There are three modules in this Layer. Lets look at each one in detail:

## tls

This module provide the GitHub authentication certificate that can be used to authenticate with AWS. The authentication certificate is provided by **OpenID Connect (OIDC)**. OIDC is a way for one system, AWS, to trust identity claims issued by a completely separate system, without having to share passwords or long-lived secret between them, using the OpenID Connect protocol (its version of the three way handshake) as the common language both sides speak.

**Core concept**

Lets look at key ideas of the OIDC:

1. One party (the Identity Provider, IdP), GitHub in this case, is responsible for authenticating an entity which could be a user, a workload, a CI pipeline. Once authenticated, the IdP issues a signed token (A JSON Web Token) containing facts about that IdP: who it is, when the token was issued, when it expires, what audience it's intended for.
2. The counter party, AWS in this case, relies on the IdP and doesn't do any authentication itself. However, its configured to trust tokens signed by that specific IdP. It verifies incoming tokens cryptographically, checking the signature against the IdP's known public keys/certificates, ensuring the token hasn't expired, and ensuring that the audience matches what's expected.
3. If the token checks out, the counter party, AWS, grants access by issuing it's own short-lived credentials in exchange, rather than the original token being used directly, forever; this is a security enhancement.

**Why this matters**
Lets look at how this applies in our case:

1. GitHub being the Identity Provider, it knows which repo, branch, and workflow is running and can confirm that.
2. AWS being the reliant counter party, doesn't know anything about GitHub org but is willing to trust tokens signed by GitHub's OIDC issuer, because we register the trust relationship via `aws_iam_openid_connect_provider` resource.
3. On every workflow run, GitHub creates a fresh JSON Web Token (JWT) that's valid for that single run. The workflow presents the token to AWS STS via `sts:AssumeRoleWithWebIdentity`, the IAM role action. AWS then verifies the signature and checks conditions in the IAM role's trust policy, what it's allowed to do. If the policy conditions are met, AWS hands back a temporary AWS credentials limited to that role, typically valid for an hour or so.

**Why this is better than the old static-key approach**

Lets look at the advantages of this:

1. There's no standing secret to leak. There's no `AWS_ACCESS_KEY_ID` sitting in a GitHub secrets vault that could be exfiltrated, accidentally logged, or reused after an employee leaves.
2. Automatic expiry: Even if a token or the resulting temporary credential were somehow intercepted, it's only useful for a short window, not indefinitely.
3. Fine-grained, declarative trust: The trust policy can pin down exactly which repo/branch/environment is allowed to assume the role; this is tighter and more auditable than "whoever has this access key."

### tls.tf

Now that we've got a good understanding of what OIDC is and how it works, lets take a closer look at how we've applied it.

```hcl
data "tls_certificate" "rr_github" {
  url = "https://token.actions.githubusercontent.com"
}
```

This data source performs a live TLS handshake against GitHub's OIDC token issuer endpoint and pulls back the certificate chain presented during that handshake i.e. this calls the GitHub API and retrieves the TLS certificate. Note, this is the same endpoint our GitHub Actions workflows will request identity tokens from. The reason for fetching it dynamically, like this, instead of hardcoding a certificate thumbprint as a string, is that GitHub rotates its TLS certificates over time; a hardcoded thumbprint would silently go stale and eventually need manual updating, when GitHub next rotates its TLS, whereas this data source re-fetches the current certificate on every `terraform apply`.

```hcl
resource "aws_iam_openid_connect_provider" "rr_github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.rr_github.certificates[0].sha1_fingerprint]
}
```

This resource was mentioned above earlier. It registers GitHub as a **trusted external IdP** inside our AWS account's IAM, the actual object AWS performs verification against when a GitHub Actions run tries to assume a role.

Lets take a look at the components in detail:

1. `url = "https://token.actions.githubusercontent.com"` - This is the OIDC issuer URL. This has to match the `iss (issuer)` claim inside the **JWT** tokens GitHub actually issues, so AWS knows which IdP's tokens this trust registration applies to.
2. `client_id_list = ["sts.amazonaws.com"]` - This is the audience (`aud` claim) GitHub Actions will request when it asks GitHub for an identity token intended for AWS. AWS verifies that the token's audience matches an entry in this list before trusting it. This is what restricts the token specifically to **"usable against AWS STS"** instead of some other service GitHub tokens might target.
3. `thumbprint_list = [data.tls_certificate.rr_github.certificates[0].sha1_fingerprint]` - This pulls the SHA1 fingerprint of the first certificate in the chain returned by the data source above. Note, this argument is effectively legacy for GitHub specifically: As of july 2023, AWS validates GitHub's OIDC identity provider connections using an internal library of trusted root certificate authorities rather than checking this thumbprint value. Esentially, this argument is a requirement for Terraform but AWS doesn't need it. Thus it's presence is for backward compatibility.

### outputs.tf

This module only has one output, `oidc_provider_arn`, which will be referenced/attached to the IAM roles.

output "oidc_provider_arn" {
value = aws_iam_openid_connect_provider.rr_github.arn
}

Above, we output the OIDC provider ARN making it available to the root module, to be consumed by the `iam` module. We will see how the above links to the IAM roles in the last section below.

## ecr

This module creates the Elastic Container Registries (ECR), a private AWS hosted Docker image registry, repositories for our frontend and backend images. Once this exists, we can run GitHub Actions workflows to push the images to the respective repos. Then have ECS pull them when we deploy Layer 4.

### ecr.tf

This file houses both the frontend and backend ECR repo creation. The code is identical for creating both. All explaination will focus on the frontend but the same applies to the backend.

**Creating ECR Repo**

Lets take a look at how we're creating frontend ECR repository:

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

As can be seen there are a few components to the resource above, so lets briefly explain them:

1. `name = "rr-${var.environment}-frontend"` - This is the repository name. This shows up in the AWS console/CLI for ECR. It is also part of the full image URI: `<account>.dkr.ecr.<region>.amazonaws.com/rr-dev-frontend`
2. `image_tag_mutability = "IMMUTABLE"` - This controls whether or not a tag, like `latest` or `v1.1` can be overwritten to point at a different image after it's been pushed. Setting it to `IMMUTABLE` means that we cannot change the tags on an image. This is very useful for deploying micro services for the following reason: If we set this to `MUTABLE` then pushing images with the same tag moves the tag to the new image. Should this new image be faulty we cannot rollback to the previous image. This is because we moved the tag and the rollback will only bring up the faulty image, it won't see the tag history. Setting it to `IMMUTABLE` means that each tag is unique and if we push a faulty image then the rollback will know the previous image's tag, and easily rollback. The example in K8S, Layer 5, is better for demonstrating this.
3. `force_delete = true` - By default AWS refuses to delete a non-empty repo as a safety measure. This setting bypasses that default behaviour so that AWS can delete all images and the repo in one go. This is ideal as we want `tf destroy` to cleanly tear down everything without having to manually purge the images before hand.
4. `image_scanning_configuration { scan_on_push = true }` - This enables ECR's basic image vulnerability scanning to run automatically when an image is pushed to the repo. AWS scans the image's OS packages against a vulnerability database to capture any common vulnerabilities and exposures, **CVEs** found in the layers.
5. `tags = ` - We've seen this countless times already.

**ECR Lifecycle policy**

Housing images in ECR incurs a storage cost. We don't want to indefinitely be pushing images, particularly in development, to lower the cost it's best to limit the number of images we keep.

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

Above, the resource, `aws_ecr_lifecycle_policy`, attaches a lifecycle policy to the repo. These are a set of automated rules ECR evaluates periodically to decide which images to delete. This is how we prevent accumulating images in our repo. Lets have a look at the components:

1. `repository = aws_ecr_repository.rr_frontend_repo.name` - This specifies which repo this lifecycle policy will apply to. Notice the implicit dependency i.e. the repo must exist before a lifecycle policy can attach to it.
2. `policy = jsonencode()` - Lifecycle policies are defined as JSON, same as the IAM policy documents.
3. `rulePriority = 1` - Like IAM policies, lifecycle policies can have multiple rules. `rulePriority` sets the order of evaluation, the lower the number the higher the priority.
4. `description  = "Keep last 5 images"` - Self explanatory: explains in words what the function does
5. `selection = {}` - This is the criteria that determins the number of images to keep. Lets look at its components:
   a. `tagStatus = "any"` - This applies to every image in the repo regardless of whether it's tagged or untagged. The alternatives are `tagged` or `untagged`.
   b. `countType = "imageCountMoreThan"` - This is the count threshold, this would delete older image(s) when the threshold is reached. The alternative is `sinceImagePushed`, which would delete images older than a given number of days.
   c. `countNumber = 5` - This is the threshold, once there are more than 5 images matching this selection, the extra images get deleted, oldest first, most recent last.
6. `action = { type = "expire" }` - This is what the policy will do; `expire` means delete if the selection criteria is met

Everything we've looked at for the frontend applies to the backend.

### outputs.tf

This module provides a few outputs but only the following outputs are passed into other modules in the root module;

1. `output "frontend_repo_arn" {}` - This is needed for the IAM frontend role.
2. `output "backend_repo_arn" {}` - This is needed for the IAM backend role.

## iam

This module is the AWS security guard which enables GitHub workflow runners to communicate with the respective ECR repos via the role they assume.

### JWT token

For the workflow runners to authenticate with AWS GitHub issues a JWT. Inside that token are key-value pairs called claims; who issued it, who it's for, which repo triggered it etc. Below is a fabricated example for the frontend, for illustration, note this is **not** the actual token:

```JSON
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

AWS evaluates this payload by running checks against the claims, line by line, to see if values match. Lets take a closer look at these **claims**:

1. `"iss": "https://token.actions.githubusercontent.com"` - This is the **Issuer** of the token. Its value matches `var.oidc_provider_arn` output. When the authentication request reaches AWS STS, AWS contacts `https://token.actions.githubusercontent.com/.well-known/jwks]` to fetch GitHubs's public cryptographic keys and verify the token's signature, target.
2. `"aud": "sts.amazonaws.com"` - This is the **Audience**, who the token was created for; it's referenced in `conditions = {}` section of the role below; its matched against `token.actions.githubusercontent.com:aud`. AWS sees `sts.amazonaws.com` which satisfies the `StringEquals` condition.
3. `"sub": "repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:ref:refs/heads/main"` - This is the subject, AWS reads the repo which satisfies the wildcard check in the `StringLike` rule below: `repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:*`.
4. `"iat": 1775030400` & `"exp": 1775031000` - These are **Issued At** and **Expiration** time. They ensure the token is currently valid and hasn't expired. Note, tokens are short-lived, usually expiring in 10-15 minutes.

Once all the checks are completed and all the conditions pass, **AWS** issues temporary access keys (`AccessKeyId`, `SecretAccessKey`, `SessionToken`) to the GitHub Actions runner.

Now that we've seen an example of the JWT and it's usecase. Lets look at the roles that use the JWT.

### iam_frontend.tf

Once again, both the frontent IAM role and the backend IAM role are identical. So we will focus on the frontend and everything we discuss applies to the backend. Lets take a closer look at the frontend file:

**aws_iam_role**

This file houses two resource definitions; an IAM role and an IAM role policy. Lets look at the IAM role first:

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

This role will be assumed by the **GitHub Actions workflow runner** when it authenticates via the OIDC JWT to push an image to the frontend ECR repo.
i.e. the workflow receives security clearance to perform any tasks specified within the role either via inline policy or attached role policy, to the mentioned resources.

Lets examin the components:

1. `name = "rr-${var.environment}-github-frontend-role"` - This is the IAM role name, following the usual project convention with prefix `rr-` and the environment `${var.environment}`.
2. `assume_role_policy = jsonencode()` - This is the trust policy, it acts as the bouncer for this IAM role. It explicitly defines who or what is allowed to assume the role. `jsonencode converts the HCL (HashiCorp Configuration Language) object into the JSON string format that AWS requires.
3. `Version = "2012-10-17"` - This is the standard, current verion of the AWS IAM policy language
4. `Statement = [{}]` - This is the core of the IAM policy, within the block `[]`, denoting an array/list, is where the permissions/rules are defined; each `{...}` represents a single rule i.e. it contains specific configuration for a single permission; it consists of:
   a. `Effect` - Are we allowing or denying access?
   b. `Action` - What specific AWS actions are permitted?
   c. `Principal/Resource` - Who is allowed to do it, and to what?
   d. `Condition` - Under what specific circumstances is this rule valid?
5. `Action = "sts:AssumeRoleWithWebIdentity"` - This allows an entity, our GitHub Actions workflow, to exchange the **JWT** for a temporary AWS credentials via AWS Security Token Service (STS)
6. `Effect = "Allow"` - This explicitly grants the permission to perform the action(s)
7. `Principal = { Federated = var.oidc_provider_arn }` - This defines the trust identity. In passing `var.oidc_provider_arn` we're telling AWS to trust our pre-configured GitHub Actions OIDC identity provider.
8. `Condition = {}` - This is the critical security guardrails: Even though AWS trusts GitHub, **the Principal**, it shouldn't let just any GitHub repository assume this role. Thus the condition restricts audience/target and the subject/originator to the specified and nothing else.
9. `"token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"` - This identifies who the token is for. Lets break it down:
   a. `token.actions.githubusercontent.com` tells AWS to look at the token claims coming specifically from GitHub's OIDC URL.
   b. `aud` tells AWS to extract the `aud` field from inside that GitHub token's JSON payload, see above section on JWT.
   c. `sts.amazonaws.com` - This is the required value, if matched then pass else fail.
   Note, this also helps prevents token replay attacks: If our workflow used the OIDC to talk to multiple third-party services e.g. AWS, Datadog and HashiCorp Vault, GitHUb would create a new token for each request. If a malicious actor somehow intercepts a token GitHub generated for HashiCorp Vault, they might try to send that stolen token to AWS to steal our AWS credentials, **a replay attack**. The `aud` condition blocks this: \*\*AWS checks the token, sees it was intended for HashiCorp Vault instead of AWS STS and immediately rejects it. Note, the use of `StringEquals` enforces an exact, case-sensitive match, character by character.
10. `"token.actions.githubusercontent.com:sub" = "repo:ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised:*"` - This restricts access to a specific repository. Lets break it down, without repetition:
    a. `sub` - This is the subject condition, it specifies the repository/originator of the request
    b. `*` - The wild card operator means any workflows running inside this repo, on any branch or tag, is allowed to assume this role. Note, without this line, any GitHub user on the planet could potentially assume our AWS role if they knew its ARN.

**aws_iam_role_policy**

Now that we have the role defined, our workflows can log into AWS. Lets now add permisions that will enable the workflow runner to complete it's tasks in other words lets specify what our workflow runners are allowed to do once they logg into AWS. This can be achieved with an `aws_iam_role_policy` resource.

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

Lets look at the components:

1. `resource "aws_iam_role_policy"` - This tells Terraform to create an **inline** IAM policy. An inline policy is baked directly into a specific role, using role ID, thus deleted when the role is deleted. Stand-alone managed policies, Customer Managed Policies, however need to be attached to the role via a **aws_iam_role_policy_attachment**.
2. `name = "rr-${var.environment}-github-frontend-policy"` - This is the name of the policy following the project convention `rr-` and specifying the environment, `var.environment`.
3. `role = aws_iam_role.rr_github_frontend_role.id` - This explicitly attaches/links these inline policy rules to the role i.e. by including the role ID here we make this role policy applicable to our frontend IAM role.
4. `policy = jsonencode()` - This is the core policy object converted into JSON format required by AWS.
5. `Statement = [...]` - This block houses the necessary permissions rules. In this case it concists of 2 permissions rules, separated by `{},`.

Lets look at the statememt in detail:

**Statement 1**

a. `Sid  = "AllowECRLogin"` - This is an optional human-readable label to easily identify what this rule does, "AllowECRLogin"
b. `Effect = "Allow"` - This enables/authorizes the action to be performed
b. `Action = "ecr:GetAuthorizationToken"` - Grants permission to generate a temporary authentication token to log into the **Docker CLI** using AWS credentials
c. `Resource = "*"` - Since getting an authorization token is an account level, registry-wide operation, not a repository-level one. AWS explicitly requires `ecr:GetAuthorizationToken` to be paired with `*`, other wise the login will fail. Note, the wildcard `*` here means any resource.

**Statement 2**
This array lists the exact, granular API calls the Docker CLI needs under the hood to pull and push image layers to AWS ECR.
Docker container images are made up of two main things: individual filesystem layers, the raw data chunks; image manifest, a JSON file listing the layers and tags.

When we run `docker push`, the Docker CLI makes several granula API calls under the hood. Here's what each action does broken down by phase:

1. **Phase 1: Checking Existing Layers & Metadata**
   Before pushing anything, Docker checks what ECR already has so it doesn't waste bandwidth re-uploading identical layers.
   a. `ecr:BatchCheckLayerAvailability` - This asks ECR "Do you already have layers with these SHA-256 hashes?" This answer is needed beause ECR uses layer deduplication: if a base layer say `Node18-alpine` is already in ECR, ECR tells Docker to skip uploading it.
   b. `ecr:GetDownloadUrlForLayer` - This provides a temporary, pre-signed download URL pointing to ECR's underlying S3 storage, for a specific image layer. This is needed when our build pipeline needs to pull or inspect an existing base layer from the registry during multi-stage builds
   c. `ecr:BatchGetImage` - This retrieves the manifest data or metadata for one or more existing image tags. It allow Docker or CI/CD tools to check to check if a specific tag already exists, inspect image digest details or fetch manifest specifications.
2. **Phase 2: Uploading missing Layers**
   If ECR doesn't have a layer, Docker uploads it in a 3-step transaction: Initiate ---> Part ---> Complete
   a. `ecr:InitiateLayerUpload` - This tells ECR: "I'm about to send you a new layer". This is needed because ECR initializes an upload session and returns a unique **Upload ID** to track the incoming data stream.
   b. `ecr:UploadLayerPart` - This streams the actual byte chunks of a layer to ECR i.e. large Docker layers are broken into smaller parts and uploaded sequentially or in parallel. Note however, our images are very small.
   c. `ecr:CompleteLayerUpload` - This tells ECR: "I've finished sending all parts for this layer". This is needed because ECR verifies the total layer checksum/digest against what was uploaded to ensure no corruption occurred, then closes the upload session and marks the layer as ready.
3. **Phase 3: Tagging & Publishing**
   Once all individual layers exist in ECR, the final step is linking them together
   a. `ecr:PutImage` - This uploads the final image manifest JSON and attaches our specified tag e.g. `:latest`, `:v1.0.2` or sha256 hash `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`. Until `PutIamge` runs, the uploaded layers are just floating data chunks in ECR. `PutImage` turns those layers into a complete, pullable Docker image inside our repository.
   b. `Resource = var.frontend_repo_arn` - This is a crucial security guardrail adhearing to **Principle of Least Privileges**: It confines the GitHub Action workflow runner's permissions to push and or delete only to this frontend ECR repo i.e. all of the actions discussed above can only be performed on this frontend ECR repo

All that we've discussed above applies equally to the backend IAM role.

### outputs.tf

This module has outputs both the IAM roles ARNs for ECR, `frontend_github_role_arn` and `backend_github_role_arn`:

```hcl
output "frontend_github_role_arn" {
  value = aws_iam_role.rr_github_frontend_role.arn
}

output "backend_github_role_arn" {
  value = aws_iam_role.rr_github_backend_role.arn
}
```

However, these outputs are not consumed by any module in this Layer. In Layer 4 and 5 we use data sources to retrieve resources created in this Layer.

## Instructions

Here is the step by step guide to deploy Layer 3 successfully:

1. Copy the name of the S3 bucket used in Layer 1
2. Open `03-aws-ecr/environments/dev/providers.tf` and replace the bucket name from `"rr-capstone-5b160b287a99a6d9"` with the value.
3. If you're using a different region, change the provider region from `"eu-west-2"` to your desired region.
4. Open `03-aws-ecr/environments/dev/shared_locals.tf` and change `Project_owner` , `s3_bucket` and add/modify/remove any other desired labels
5. If on Linux change directory to the Layer 3 dev directory `cd infrastructure/03-aws-ecr/environments/dev`
6. Create an alias for terraform `alias tf=terraform`, this is easier than writing out the long word
7. Setup then **export** the GitHub PAT, the instructions to do this are in [Setting-up-GitHub-PAT-Manually.txt](https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised/blob/main/infrastructure/03-aws-ecr/documents/Setting-up-GitHub-PAT-Manually.txt)
   Note, keep the GitHub PAT in mind, we'll need to export it in later Layers.
8. Initialize terraform: `tf init`
9. Run terraform plan: `tf plan` review the outputs and if you're happy proceed to the next command
10. Run terraform apply, with caution `tf apply`, or if you trusted the plan `tf apply -auto-approve`
11. Congrats, you've deployed your Layer 3, ECR. Lets now move onto ECS.
