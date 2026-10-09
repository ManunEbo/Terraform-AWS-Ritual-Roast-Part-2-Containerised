# Ritual Roast — Multi-Stack Project

## Background

Ritual Roast is a fictitious company running an online recipe contest: Visitors complete the online form, passing in their name, email, and a recipe; a table on the same page shows all submissions; a countdown timer marks the deadline. That's the whole surface of the product, and it's deliberately simple because the recipe contest isn't really the subject of this repository. **What's actually being built here is a from-scratch, production-style AWS platform** on which the same application is deployed two completely different ways:

1. **Combined AWS Elastic Container Registry (ECR) with AWS Elastic Container Service (ECS)** - Pulls frontend and backend container images from ECR and deploys them using severless ECS with Fargate.
2. **Production grade Kubernetes (K3s) Cluster** - Self managed Kubernetes cluster (**K3s**) with GitOps ArgoCD and Istio mesh. Pulls `v1` and `v2` images from GitHub Container Registry (ghcr.io) and implements deployment strategies via Istio mesh; Canary, blue-green, and shadow deployment. Further monitoring/observability is facilitated by kiali app and grafana dashboards.

## Project Evolution & Motivation

This project is the second in a three-part series based on the architecture concepts taught in the [AWS Solutions Architect SAA-C03 capstone course](https://www.udemy.com/course/aws-solutions-architect-capstone-projects/) on Udemy. That course builds its infrastructure by hand, clicking through the AWS Console. This series builds the same ideas — and considerably more as **Infrastructure as Code (IaC)**.

## Readership objective

Every document in this repository, including this one, meets the following objective

1. **A learning resource for beginners** - Someone with no cloud or infrastructure background should be able to read any README.md herein and come away understanding **what each component does and why it exists**, without pre-exposure to Terraform, Kubernetes, or AWS.
2. **A technical demonstration** - Someone evaluating engineering skill should be able to read the same documents and see the actual reasoning behind each design decision — not just what was built, but the trade-off that was weighed and why it was resolved the way it was.

## How to read this repository

There is a lot here: five independent Terraform layers, four application images, two GitHub Actions workflows, and claude code AI assistance. Nobody needs to read all of it in one sitting. Pick a starting point and go from there:

| You are…                                                          | Start here                                                                                                     |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| A recruiter, or curious about the project generally               | Keep reading this page, it will give you a good summary of the project                                         |
| Interested in the applications themselves (frontend/backend code) | See [`apps/`](#the-applications-v1-vs-v2)                                                                      |
| A Platform/Cloud engineer interested in workflow automation       | See [`.github/workflows/README.md`](.github/workflows/README.md) and [`.github/workflows`](.github/workflows/) |
| A platform/cloud engineer, interested in the infrastructure       | See [`infrastructure/`](#the-five-infrastructure-layers), read the five layers in order                        |
| Curious how this was built with an AI coding assistant            | See [`.claude/README.md`](.claude/README.md) and [`CLAUDE.md`](CLAUDE.md)                                      |

## The shape of the project

The repository is organised into four top-level directories:

| Directory       | Description                                                                         |
| --------------- | ----------------------------------------------------------------------------------- |
| .claude/        | AI assistance instructions/commands, Agent definitions and guardrails               |
| .github/        | The GitHub Actions workflows that pushes every change in apps/ to ECR or ghcr.io    |
| apps/           | What runs — the four container images (two competing implementations `v1` and `v2`) |
| infrastructure/ | Where it runs — five independently-deployed Terraform layers                        |

## The five infrastructure layers

| Layer                                               | Builds                                                                                                                                                                    | Phase            |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| [`01-aws-vpc`](infrastructure/01-aws-vpc/README.md) | The network: a VPC, subnets across three Availability Zones, and the one public load balancer every later layer shares.                                                   | Always on        |
| [`02-aws-rds`](infrastructure/02-aws-rds/README.md) | One shared, Multi-AZ MySQL database, with credentials that rotate themselves automatically.                                                                               | Always on        |
| [`03-aws-ecr`](infrastructure/03-aws-ecr/README.md) | A private container registry, plus GitHub Actions CI that authenticates with no stored AWS password.                                                                      | ECS phase        |
| [`04-aws-ecs`](infrastructure/04-aws-ecs/README.md) | The application running on AWS Fargate, behind its own internal load balancer.                                                                                            | ECS phase        |
| [`05-aws-k8s`](infrastructure/05-aws-k8s/README.md) | A self-managed Kubernetes cluster (K3s, on plain EC2) running an Istio service mesh and an ArgoCD GitOps pipeline — where **both** application versions run side by side. | Kubernetes phase |

## 🛠️ Technology Stack

| Category                        | Technology / Tool                          | Purpose in Project                                                                                                                       |
| :------------------------------ | :----------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------- |
| **Infrastructure as Code**      | **Terraform**                              | Declarative IaC structured into 5 decoupled, isolated layers (`VPC`, `RDS`, `ECR/CI`, `ECS/Fargate`, `K3s/Istio`).                       |
|                                 | **AWS Native Data Sources**                | Dynamic inter-layer resource lookups (`data "aws_vpc"`, `data "aws_subnets"`) eliminating state coupling (`terraform_remote_state`).     |
|                                 | **S3 & DynamoDB**                          | Remote backend state storage (`.tfstate`) and distributed concurrency state locking.                                                     |
|                                 | **HCL Provider Locks**                     | Deterministic plugin version pinning (`.terraform.lock.hcl`) across local and CI/CD pipelines.                                           |
| **AWS Compute & Networking**    | **AWS VPC**                                | Core network foundation with public and private subnet tiers, Internet Gateways, NAT Gateways, and Route Tables.                         |
|                                 | **AWS EC2**                                | Virtual machine instances powering host compute and K3s cluster nodes (Layer 5).                                                         |
|                                 | **AWS Elastic Load Balancing (ALB / NLB)** | Application & Network Load Balancers managing public traffic ingress, health checks, and target group routing.                           |
|                                 | **AWS ECS (Fargate)**                      | Serverless container execution engine running microservices (Layer 4).                                                                   |
|                                 | **AWS Lambda & Layers**                    | Event-driven serverless compute leveraging shared runtime dependency layers.                                                             |
| **AWS Data & Governance**       | **AWS RDS (MySQL)**                        | Managed relational database engine with automated password generation and security group isolation.                                      |
|                                 | **AWS ECR**                                | Private container image registry backing ECS and K3s deployments.                                                                        |
|                                 | **AWS Secrets Manager & SSM**              | Secure handling and parameter distribution of database credentials, runtime keys, and environment configs.                               |
| **Containers & Orchestration**  | **Docker**                                 | Containerization engine and multi-stage image packaging for microservice workloads.                                                      |
|                                 | **K3s**                                    | Lightweight, highly resilient Kubernetes distribution for cluster orchestration.                                                         |
|                                 | **Calico**                                 | Container Network Interface (CNI) providing pod networking and fine-grained `NetworkPolicy` security enforcement.                        |
|                                 | **Istio**                                  | Service mesh managing ingress gateway routing, dynamic traffic distribution, and pod-to-pod mTLS encryption.                             |
|                                 | **ArgoCD**                                 | GitOps continuous delivery controller automating Kubernetes manifest deployment and drift reconciliation.                                |
|                                 | **Helm**                                   | Kubernetes package manager for templating and releasing cluster services, add-ons, and mesh configurations.                              |
| **Application & Microservices** | **Go**                                     | High-performance compiled backend microservices and custom infrastructure tooling.                                                       |
|                                 | **Python & Flask**                         | Lightweight REST APIs, backend service logic, and automated data processing scripts.                                                     |
|                                 | **Next.js & Vite**                         | Modern full-stack React framework and build tool powering the Ritual Roast frontend interface.                                           |
| **Observability & Monitoring**  | **Prometheus**                             | Metrics scraping, time-series storage, and alerting engine for Kubernetes and cloud infrastructure telemetry.                            |
|                                 | **Grafana**                                | Observability visualization platform providing real-time dashboards for metrics, mesh traffic, and resource usage.                       |
| **CI/CD & FinOps**              | **GitHub Actions**                         | Automated CI/CD pipelines with AWS OIDC authentication for sequential Terraform deployments.                                             |
|                                 | **Infracost CLI**                          | Automated per-layer cloud cost estimation (`infracost-config.yml`).                                                                      |
|                                 | **Bash & `jq`**                            | Shell automation parsing raw JSON cost outputs into structured FinOps CSV reports (`unified_infracost_raw.csv`, `per_layer_totals.csv`). |
| **AI Engine & Agent Tooling**   | **Claude & Claude Code**                   | Terminal-native AI execution, sub-agent configurations (`.claude/agents/`), automated refactoring, and agentic workflows.                |
|                                 | **Gemini**                                 | Multi-modal AI thought partnership, architectural review, technical validation, and documentation synthesis.                             |

# Project Concluding remarks

Far too often, when I've wanted to learn a new technology I jumped to GitHub looking for a great repo that will gently introduce the topic and guide me through the material to PRO level in a digestable orderly fashion with plenty of examples. 100% of the time, I came away disappointed:

1. Most repos were either too advanced and taking the liberty of technical jargon or not worth reading.
2. There were no instructions or step by step implementation guides that I could follow to deploy
3. The author is always difficult to reach.

I wanted these series of repos on Ritual Roast to be the learning resource I needed if I was learning Terraform with AWS from scratch. However, it's not perfect! The following section's README.md were written by Claude code and I verified them and made minor changes.

1. **`.claude/`** - A single README.md sits at the base of this directory
2. **`.github/workflows/`** - A single README.md can be found at the base of this directory
3. **`apps/*`** - Each of the four images directories have their own README.md

I did not rewrite these READMEs to make them more educational simply because these were not the main focus of the project. The main focus of the project was everything under `infrastructure/`. In each of the sub directories, there's a single README.md which covers the deployment file by file and explains each resource and its components step by step, unless it's something we've already covered at that point.

## Instructions

As you explore the repo, you will find that each layer in `infrastructure/` ends with **Instructions**. I recommend that you read the whole respective README.md before commencing the deployment. Please ensure you've read the instructions carefully and completed every task before running `tf plan` or `tf apply`.

## AWS Costs

**These deployments will incur a cost on your account**. To minimize the cost here are my best tips:

1. **Read all the repos first** - It would be a waste of your time and money to jump to the instructions and deploy without having studied and or understood what the deployment is doing.
2. Avoid leaving the deployment running for long hours on end.
3. Layer 5 is the most costly, it is possible to run it on smaller instance types to reduce costs e.g. `t3.small` but I opted for slightly more headroom with `t3.medium`.

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
If you have any questions feel free to connect on [LinkedIn](https://www.linkedin.com/in/elvy-kamunyoko-manunebo/). If it's a question that AI can answer for you quickly, then please take that root instead. For all else, reach out, I might not get back to you straight away but rest assured I will.

Best regards

Elvy

# License & Disclaimer

## License

Copyright © 2026 Elvy Manun'Ebo.

This project is licensed under the [MIT License](LICENSE) - see the [LICENSE](LICENSE) file for details. You are free to use, modify, and distribute this software for educational and personal purposes.

## AWS Cloud & Infrastructure Disclaimer

- **Cost Liability:** This repository contains Terraform configurations and deployment scripts that provision live resources on Amazon Web Services (AWS). Running these templates **will incur charges** on your AWS account. The author accepts no responsibility or liability for any AWS bills, unexpected costs, or financial damages resulting from the execution of this code.

- **Provided "As-Is":** The code and documentation are provided "as is" without warranty of any kind, express or implied. Always review Terraform plans (`terraform plan`) and evaluate security configurations (e.g., IAM roles, Security Groups, public endpoints) before applying them in an AWS environment.
