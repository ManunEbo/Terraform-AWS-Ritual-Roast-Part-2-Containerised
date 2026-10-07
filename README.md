# Ritual Roast — Multi-Stack Project

## 1. Background

Ritual Roast is a fictitious company running an online recipe contest: Visitors complete the online form, passing in their name, email, and a recipe; a table on the same page shows all submissions; a countdown timer marks the deadline. That's the whole surface of the product, and it's deliberately simple because the recipe contest isn't really the subject of this repository. **What's actually being built here is a from-scratch, production-style AWS platform** on which the same application is deployed two completely different ways:

1. **Combined AWS Elastic Container Registry (ECR) with AWS Elastic Container Service (ECS)** - Pulls frontend and backend container images from ECR and deploys them using severless ECS with Fargate.
2. **Production grade Kubernetes (K3s) Cluster** - Self managed Kubernetes cluster (**K3s**) with GitOps ArgoCD and Istio mesh. Pulls `v1` and `v2` images from GitHub Container Registry (ghcr.io) and implements deployment strategies via Istio mesh; Canary, blue-green, and shadow deployment. Further monitoring/observability is facilitated by kiali app and grafana dashboards.

## 2. Project Evolution & Motivation

This project is the second in a three-part series based on the architecture concepts taught in the [AWS Solutions Architect SAA-C03 capstone course](https://www.udemy.com/course/aws-solutions-architect-capstone-projects/) on Udemy. That course builds its infrastructure by hand, clicking through the AWS Console. This series builds the same ideas — and considerably more as **Infrastructure as Code (IaC)**.

## 3. Readership objective

Every document in this repository, including this one, meets the following objective

1. **A learning resource for beginners** - Someone with no cloud or infrastructure background should be able to read any README.md herein and come away understanding **what each component does and why it exists**, without pre-exposure to Terraform, Kubernetes, or AWS.
2. **A technical demonstration** - Someone evaluating engineering skill should be able to read the same documents and see the actual reasoning behind each design decision — not just what was built, but the trade-off that was weighed and why it was resolved the way it was.

## 4. How to read this repository

There is a lot here: five independent Terraform layers, four application images, two GitHub Actions workflows, and claude code AI assistance. Nobody needs to read all of it in one sitting. Pick a starting point and go from there:

| You are…                                                          | Start here                                                                                                 |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| A recruiter, or curious about the project generally               | Keep reading this page — it's self-contained                                                               |
| Interested in the applications themselves (frontend/backend code) | [`apps/`](#the-applications-v1-vs-v2) below                                                                |
| A Platform/Cloud engineer interested in workflow automation       | [`.github/workflows/README.md`](.github/workflows/README.md) and [`.github/workflows`](.github/workflows/) |
| A platform/cloud engineer, interested in the infrastructure       | [`infrastructure/`](#the-five-infrastructure-layers) below, read the five layers in order                  |
| Curious how this was built with an AI coding assistant            | [`.claude/README.md`](.claude/README.md) and [`CLAUDE.md`](CLAUDE.md)                                      |

## 5. The shape of the project

The repository is organised into four top-level directories:

| Directory       | Description                                                                         |
| --------------- | ----------------------------------------------------------------------------------- |
| .claude/        | AI assistance instructions/commands, Agent definitions and guardrails               |
| .github/        | The GitHub Actions workflows that pushes every change in apps/ to ECR or ghcr.io    |
| apps/           | What runs — the four container images (two competing implementations `v1` and `v2`) |
| infrastructure/ | Where it runs — five independently-deployed Terraform layers                        |

## 6. The five infrastructure layers

| Layer                                               | Builds                                                                                                                                                                    | Phase            |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| [`01-aws-vpc`](infrastructure/01-aws-vpc/README.md) | The network: a VPC, subnets across three Availability Zones, and the one public load balancer every later layer shares.                                                   | Always on        |
| [`02-aws-rds`](infrastructure/02-aws-rds/README.md) | One shared, Multi-AZ MySQL database, with credentials that rotate themselves automatically.                                                                               | Always on        |
| [`03-aws-ecr`](infrastructure/03-aws-ecr/README.md) | A private container registry, plus GitHub Actions CI that authenticates with no stored AWS password.                                                                      | ECS phase        |
| [`04-aws-ecs`](infrastructure/04-aws-ecs/README.md) | The application running on AWS Fargate, behind its own internal load balancer.                                                                                            | ECS phase        |
| [`05-aws-k8s`](infrastructure/05-aws-k8s/README.md) | A self-managed Kubernetes cluster (K3s, on plain EC2) running an Istio service mesh and an ArgoCD GitOps pipeline — where **both** application versions run side by side. | Kubernetes phase |

# Introduction to Terraform

Before we get deep into the Terraform code, lets explain a few foundational concepts of Terraform that will prepare us for the deep dive in `infrastructure/`:

## 1. A layered approach

A layered infrastructure architecture decouples foundation, data, image registry, compute, and service mesh tiers into independent, modular building blocks. Think of a layered project structure like building a house with **modular LEGO blocks** rather than pouring a single, solid block of concrete.

**Key advantages of a Layered Architecture**

1. **Modular Stacking and Unstacking** - Downstream layers (Layer 4 & 5) consume outputs like subnet IDs or database connection strings from upstream layers (Layer 1 & 2) without modifying them. This makes swapping out major components such as replacing Layer 4 (ECS) with Layer 5 (Kubernetes) as simple as destroying or adding a single layer while leaving core network and database foundations untouched. The new layer simply attaches or plugs in.

   **The simplified explanation** - Because each layer sits neatly on top of the one beneath it, metaphorically, it gives us the flexibility to build, replace or swap an upper floor without tearing down the lower levels. For example, moving the application from AWS ECS (Layer 4) to Kubernetes (Layer 5) was straight forward because the core network (Layer 1) and the database (Layer 2) stayed right where they were.

2. **Blast radius isolation (Fire doors for mistakes)** - Infrastructure failure or accidental terraform destroys are contained within their specific layer. A misconfiguration while updating Kubernetes workloads (Layer 5) cannot corrupt our persistent MySQL database (Layer 2) or wipe out our VPC routes (Layer 1)

   **The simplified explanation** - If something goes wrong, like accidental deletion or a typo in an application update, the damage is strictly contained within that single room. A mistake on the top floor cannot accidentaly burn down the house, wipe out our database, or knock out our core network setup.

3. **Decoupled deployment lifecycles (Changing lightbulbs vs. rewiring the house)** - Low-level infrastructure (VPCs, subnets, database clusters) changes infrequently, whereas application compute layers deploy daily. Separating state files ensures we never risk modifying core network primitives during routine application updates.

   **The simplified explanation** - Core networks and databases rarely change once built but application code changes every single day. Keeping them separate means developers can make daily tweaks to the app without touching or risking the heavy plumbing underneath.

4. **Tailored security keys** - We operate under the **Principle of Least Privileges**: Entities within each layer only get the specific credentials necessary to complete their tasks e.g. GitHub Actions workflows only get credentials to drop off container images in the ECR registry (Layer 3), but it never gets credentials to retrieve secrets from Secrets Manager containing our database passwords (Layer 2).

5. **Working with 5 small sub-directories instead of 1 giant master directory** - Instead of opening a massive, messy directory every time we want to make a tiny change, each layer is structured for specific intent. This keeps updates fast, eliminates guesswork, and makes fixing bugs vastly simpler.

## 1. Moduler setup

A Terraform deployment consists of many groups of resources interconnecting to construct the deployment. It is best practice to organise these resources in a structure that isolates one specific group from another i.e. we don't want to mix up the creation of networking resources such as VPC, subnets and route tables with the creation of the database, lambda functions, security groups etc, these are best kept separate. This simplifies finding resources and making the codebase easy for others to pick up.

We define such a separation of concern as a module. A module should have the following essential files:

1. **variables.tf** - This file defines the variables and their formats that will be used in this module. The variables can also take inputs passed in from other modules via the root module. This is how modules share variables.
2. **outputs.tf** - This file defines the variables that this modules is sharing with the other modules. The root module can pull this and pass it on.

Other than these essentials, the module will have files that uniquely define specific resources that will be referenced in the outputs.tf i.e. shared with other modules. **Such files are the whole point of having modules**. There maybe several modules in a project, each one focusing on a specific required task.

## 2. Configuring the environment (The management module)

In a layered infrastructure setup a directory like `01-aws-vpc/environments/dev` acts as the **Control center for our development environment**. Metaphorically, if our Terraform modules are the generic templates for building a house, then the `dev` folder is the specific work order detailing exactly how to build the **"testing"** version of that house. The following is a list of responsibilities for the environment directory:

1. **Setting environment specific variables (The dials)** - The underlying modules like the Layer 1 `vpc` module are written to be reusable i.e. environment agnostic; they don't know if they are being built for production or testing. The `dev` folder contains the specific configuration files such as `variables.tf` that define the variables and their formats that will be used in this specific environment e.g. instance size, network CIDR range etc. When we run `terraform apply` on the `dev` environment, Terraform will pass the values from `dev` environment to the modules and deploy the architecture. In cases where there is identical `prod` or `staging` sub directories next to the `dev`, we can easily pass different values to corresponding variables in such environments and deploy all three environments simultaneously.

2. **Terraform lock file `.terraform.lock.hcl`** - This is the **Provider Dependency Lock file**. When we write Terraform code, we rely on external plugins called "providers", like the AWS provider to talk to AWS. These plugins are version controlled. When we run `terraform init` for the first time, Terraform downloads those providers. It then creates the `.terraform.lock.hcl` file, recording the **exact version numbers** and **cryptographic hashes**, unique digital fingerprints, of the downloaded plugins. On any future runs, Terraform reads this lock file and forces our system to use those exact versions, even if AWS or HashiCorp released a newer version overnight. **Note, this lock file contains no sensitive data thus it can be stored in our Git repository.**

   **What are we using it for?**
   1. **Guaranteed consistency** - It solves the _"it works on my machine"_ problem. By committing it to Git, we guarantee that our local laptop, our co-worker's laptop and our automated GitHub Actions CI/CD pipeline are all using the exact same version of the AWS provider.

   2. **Preventing unexpected breakages** - If the AWS provider releases a major update with breaking changes, our infrastructure won't suddenly fail to deploy, because the lock file pins us to the older, **known-working**, version until we explicitly run `terraform init -upgrade`.

   3. **Security** - Because it stores cryptographic hashes, Terraform will block the deployment if it detects that the provider code was tampered with maliciously.

3. **Terraform state lock file `terraform.state.lock`** - This is a temporary safety mechanism that prevents any two entities (people and or processes) from modifying the same infrastructure state file at the exact same time.

   **How does it work**
   1. **Lock acquisition** - Whenever we execute a command that reads or modifies state such as `terraform plan`, `terraform apply`, or `terraform destroy`, Terraform automatically attempts to create a lock before making any changes.

   2. **Recording lock info** - It creates a temporary record containing details about the current operation: A unique **Lock ID**; the user or system running the command e.g. our local username or GitHub Actions runner; the timestamp when the operation started; the operation type e.g. `OperationTypeApply`.

   3. **Blocking concurrent runs** - If another engineer or CI/CD pipeline tries to run `terraform apply` on that same layer while the lock is active, Terraform reads the lock, stops immediately, and displays an error showing who is currently holding the lock.

   4. **Lock release** - Once the command completes successfully or fails safely, Terraform deletes the lock record, allowing the next queued operation to run.

   **How are we using it**
   1. **Preventing state file corruption** - If two entities such as a developer and GitHub Actions ran `terraform apply` on Layer 1 at the same time, both would try to write to the same AWS S3 state file simultaneously, resulting in a corrupted, unusable state file.

   2. **Enforcing order in CI/CD** - This file ensures automated pipelines and team members wait their turn, preserving a single, consistent sequence of changes.

   3. **Auditability and debugging** - If a deployment is stuck or blocked, the state lock error provides immediate visibility into who holds the lock, on what machine, and when the operation started, making it easy to identify stale or hanging deployments.

4. **State file isolation** - Terraform tracks everything it builds in a state file. **It's Terraform's single source of truth**, a JSON file that maps our declarative code to real-world cloud resources.

   **How does it work?**
   1. **Resource mapping** - When we declare `resource "aws_vpc" "main"`, Terraform provisions it in AWS, gets back an ID like `vpc-0a1b2c3d4e` and records that mapping in the state file.
   2. **Metadata & attribute tracking** - It stores the exact live attributes of our managed infrastructure; IP addresses, Amazon resource names (ARNs), route tables, and secrets.
   3. **Drift detection** - Whenever we run `terraform plan` or `terraform apply`, Terraform performs a three-way comparison between:
      1. our local `.tf` code, what we want.

      2. The `.tfstate` file, what Terraform thinks exists.

      3. The real cloud environment, what actually exists in AWS.

   4. **Storing the state file** - There are several options when it comes to storing the `terraform.tfstate` file:
      1. **Local storage** - Here we save the file directly in our project folder. This is problematic for team environments as it risks file loss, concurrent overwritten changes, and exposes secrets in plain text on our laptop.

      2. **Remote backends (Recommended)** - There are a few options here:
         1. **AWS S3 bucket** a central encrypted object storage, standard for AWS architectures, this is what we're using
         2. **Terraform Cloud / HashiCorp Cloud Platform (HCP)**, managed state handling, access controls, and policy enforcement
         3. **Azure blob Storage / Google Cloud Storage (GCS)**, these are object storage equivalents for Azure and GCP environments respectively
         4. **HTTP / GitLab / GitHub State Storage**, API-based remote state management from GitHub

   5. **Comparing the files** - These three files manage completely different aspects of Terraform stability and safety:
      1. **`terraform.lock.hcl`** - ensures everyone uses the exact same plugin binaries to build the code
      2. **`terraform.state.lock`** - blocks multiple engineers or CI/CD pipelines from modifying the state file simultaneously.
      3. **`terraform.tfstate`** - records the final result of those builds once the lock releases.
   6. **How are we using the state file**
      1. **Decoupled layer states** - In this multi-layered architecture, Layer 1 - Layer 5, every layer maintains its own isolated state file in AWS S3 e.g. `dev/layer1-vpc/terraform.tfstate`. This isolates blast radius so an apply in Layer 5 never risks corrupting Layer 1.

      2. **Secure remote storage & team collaboration** - Storing state files in an encrypted AWS S3 bucket keeps sensitive infrastructure data off local machines while allowing developers and GitHub Actions to share a single ground truth.

5. **The execution point** - This is the directory where we actually run our commands (`terraform init`, `terraform plan`, `terraform apply`). The code inside this folder pulls in the generic layers we built (Layer 1, Layer 2 etc), injects the `dev` variables into them, reads the `dev` remote state, and orchestrates the actual deployment to AWS.

Note, these multiple environments; `dev`, `staging`, `prod`; exist as separate directories, their configuration are applied directly to the modules within that layer. **That makes the code base flexible such that we can deploy the same code in all environments simultaneously**, the difference being the values we pass to them, which could dramatically change the outcome.

## The root module

Since we're using a layered approach, each layer consists of a root module, which is under the corresponding `environments/dev/` subdirectory, this is essentially the management module for the environment. The root module will also have the same essential files above in additions to **main.tf**. This file defines all corresponding modules in the layer and passes values as input parameters to the module being defined.

In Layer 1 [README.md](https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised/blob/main/infrastructure/01-aws-vpc/README.md) we delve into the details of these files.

## Variable precedence in Terraform

Terraform evaluates variables in a strict hierarchy where sources loaded **later** override values set by **earlier** sources i.e. **Terraform's internal loading pipeline** during execution loads values in the order of precedence, replacing values previously set by lower priority sources with the higher priority sourced values.

**Variable precedence hierarchy, Lowest to Highest**

1. **Variable block defaults (Lowest priority)** - The default value declared directly within the `variable "x" {default = "value"}` block in `.tf` files. This acts as a safe fallback if no other value source is provided.
2. **Environment variables `TF_VAR_name`** - These values are passed in via the command line prefixed with `TF_VAR`, Terraform looks for such values. They are useful for injecting non-committed settings or sensitive credentials into local shell sessions or build agents without modifying disk files.
3. **`terraform.tfvars` / `terraform.tfvars.json`** - These are standard key value pairs assignment files automatically recognized and loaded by Terraform when present in the root module directory. It serves as the primary configuration file for environment-specific variables.
4. **`*.auto.tfvars` / `*.auto.tfvars.json`** - Automatically loaded variable files processed in alphabetical order by filename e.g. `a.auto.tfvars` is processed before `b.auto.tfvars`. This is useful when splitting large variable lists into logical, self-contained files e.g. `01-network.auto.tfvars`, `02-database.auto.tfvars` while overriding base `terraform.tfvars` values.
5. **`-var` and `-var-file` command-line flags (Highest priority)** - These are values passed into Terraform directly from the CLI at runtime e.g. `terraform plan -var="environment=dev"` or `-var-file="override.tfvars"`. If multiple `-var` or `-var-file` flags are supplied, Terraform processes them in the exact order they appear on the command line. This is used for immediate, high priority overrides, ad-hoc testing, or dynamic parameter injection in automated CI/CD pipelines.

**Why the precedence is structured in this order**

The precedence order is built around the principle of explicit intent and locality:

1. **From static defaults to dynamic overrides** - Baseline defaults hardcoded in module definitions `default =...` represent broad assumptions. As we move up the hierarchy towards runtime command line flags `-var`, the input source becomes more localized and explicitly intended for that specific deployment execution.

2. **Separation of code and configuration** - By placing file based configuration `.tfvars` above environment settings `TF_VAR_...`, Terraform ensures project specific, committed configuration files take precedence over lingering shell environment variables.

3. **Granular automation control** - Giving command line options `-var`/`-var-file` ultimate priority allows human operators and CI/CD pipelines to temporarily force specific behaviour without dirtying committed project files or modifying persistent environment variables.

## Data sources

A data source in Terraform is a read-only query that fetches real time information directly from an external source or cloud provider without creating, modifying, or managing that resource.

**How data sources work**

1.  **Declaration** - We declare a `data` block to tell Terraform what to look for, **resource type** and how to find it, using **`filters` like `tag: Name`, or `ID`**

Here's an example:

```hcl
data "aws_vpc" "main" {
filter {
   name   = "tag:Name"
   values = ["rr-dev-RR-vpc"]
}
}
```

Here we're looking for a `aws_vpc` resource type filtering by tags and the matching value is `"rr-dev-RR-vpc"`. This will return all matching values. `"main"` is the name we're attaching to this data source for referencing the returned resource.

2.  **API query** - When Terraform runs, it makes a direct API call to AWS using those filters.
3.  **Attribute exposure** - AWS responds with the live resource's details and Terraform makes those attributes available to the rest of our configuration using the syntax `data.<TYPE>.<NAME>.<ATTRIBUTE>` e.g. `data.aws_vpc.main.id` or `data.aws_vpc.main.cidr_block`.

**Advantages over other methods**

Compared to hardcoding values or using **state-coupling mechanisms** like `terraform_remote_state` which requires knowing the exact S3 bucket path and exact output variable names:

1. **Complete layer decoupling (vs `terraform_remote_state`)** - Downstream layers don't need access to upstream layer S3 state files, nor do they care how upstream layers named their output variables. They only care about what actually exists in AWS.
2. **Eliminates hardcoding (vs. manual input variables)** - We never have to manually copy and paste dynamic AWS IDs, like `vpc-0a1b2c3d` or subnet IDs, into our `terraform.tfvars` file across environments.
3. **Live ground truth** - Data sources evaluate the live AWS environment at runtime, ensuring our configurations operate against current infrastructure state rather than stale state files.
4. **Refactoring resilience** - We can completely restructure or rewrite Layer 1's code from scratch, as long as the deployed VPC retains its expected tag in AWS, Layer 2 will continue to discover it without breaking.
5. **Granular security** - Downstream environments only require standard AWS read permissions `ec2:DescribeVpcs` rather than elevated read access to S3 backend buckets containing sensitive state data.

**How are we using data sources**

In the Ritual Roast architecture, data sources serve as the **glue between isolated layers**. they enable us to make use of resources created in upstream layers in flexible dynamic ways. Below are some example use cases:

1. **Network discovery** - Layer 2 (RDS), Layer 4 (ECS) and Layer 5 (K3s) use `data "aws_vpc"` and `data "aws_subnets"` to discover Layer 1's VPC ID and private subnet tiers dynamically based on environment tags.
2. **Container image lookups** - Layer 4 and use `data "aws_ecr_repository"` to retrieve registry URLs created in Layer 3 (ECR) for container deployment with ECS.
3. **Secret & config management** - Downstream layers use `data "aws_secretsmanager_secret_version"` to read runtime/latest database credentials generated in upstream layers without passing sensitive plain-text strings through code.

# Project Concluding remarks

Far too often, when I've wanted to learn a new technology I jumped to GitHub looking for a great repo that will gently introduce the topic and guide me through the material to PRO level in a digestable orderly fashion with plenty of examples. 100% of the time, I came away disappointed:

1. Most repos were either too advanced or not worth reading.
2. There were no instructions or step by step implementation guides that I could follow to deploy
3. The author is always difficult to reach.

I wanted these series of repos on Ritual Roast to be the learning resource I needed if I was learning Terraform with AWS from scratch. However, it's not perfect! The following section's README.md were written by Claude code and I verified them.

1. **`.claude/`** - A single README.md sits at the base of this directory
2. **`.github/workflows/`** - A single README.md can be found at the base of this directory
3. **`apps/*`** - Each of the four images directories have their own README.md

I did not rewrite these READMEs to make them more educational simply because these were not the main focus of the project. The main focus of the project was everything under `infrastructure/`. In each of the sub directories, there's a single README.md which covers the deployment file by file and explains each resource and its components step by step, unless it's something we've already covered at that point.

## Infracost

The aim was to use Infracost to estimate the montly AWS cost of running Ritual Roast deployment and to feed those figures into an Excel dashboard workbook.

In every layer of `infrastructure/` you will see the following file `environment/dev/infracost-usage.yml`. These files are mapped in `infracost-config.yml` in the root directory which is read by the executable file `extract_all_costs.sh`. The executable automates FinOps cloud cost analysis across our infrastructure layers using Infracost and parses the output into two structured CSV reports.

It performs the following steps:

1. **Validates prerequisites** - Ensures `jq`, `infracost`, and `infracost-config.yml` are present in the repo root before running. Otherwise it exits.
2. **Generates cost data** - RUNS `infracost breakdown` across all configured layers to generate a single raw JSON cost evaluation (`infracost_breakdown.json`). Note, these costs are in GBP.
3. **Exports Itemized breakdown (`unified_infracost_raw.csv`)** - Uses `jq` to parse every individual resource, tagging it by layer alongside its estimated monthly cost, formatted for spreadsheet/dashboard macro ingestion. ECS (Layer 4) and K8s (Layer 5) outputs are kept as separate layers for comparison. This file is then read by the Excel dashboard.
4. **Exports summary totals (`per_layer_totals.csv`)** - Aggregates the total monthly costs for each layer and appends a calculated grand total row across the entire architecture. This file provides summaries just for a glance, it's not used for anything else

I may explore this further in the future but for now it will remain incomplete and out of scope.

## Last words

So enjoy my work, I laboured for many months to be able to bring this to you. I hope it helps you take the next step forward in your career into DevOps.
If you have any questions feel free to connect on [LinkedIn](https://www.linkedin.com/in/elvy-kamunyoko-manunebo/). I might not get back to you straight away but rest assured I will.

Best regards

Elvy

# License & Disclaimer

## License

Copyright © 2026 Elvy Manun'Ebo.

This project is licensed under the [MIT License](LICENSE) - see the [LICENSE](LICENSE) file for details. You are free to use, modify, and distribute this software for educational and personal purposes.

## AWS Cloud & Infrastructure Disclaimer

- **Cost Liability:** This repository contains Terraform configurations and deployment scripts that provision live resources on Amazon Web Services (AWS). Running these templates **will incur charges** on your AWS account. The author accepts no responsibility or liability for any AWS bills, unexpected costs, or financial damages resulting from the execution of this code.

- **Provided "As-Is":** The code and documentation are provided "as is" without warranty of any kind, express or implied. Always review Terraform plans (`terraform plan`) and evaluate security configurations (e.g., IAM roles, Security Groups, public endpoints) before applying them in an AWS environment.
