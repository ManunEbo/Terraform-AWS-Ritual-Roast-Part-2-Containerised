# Ritual Roast — one app, two cloud platforms, built as code

> A deliberately simple recipe-contest web app, deployed two completely different ways — first on AWS
> ECS/Fargate, then on a hand-built Kubernetes cluster — over one shared, Terraform-defined
> foundation, so the two platforms can be compared under live, shifting traffic.

Ritual Roast is a fictitious company running an online recipe contest: a visitor fills in their
name, email, and a recipe; a table on the same page shows everyone else's submissions; a countdown
timer marks the deadline. That's the whole surface of the product, and it's deliberately simple —
because the recipe contest isn't really the subject of this repository. **What's actually being built
here is a from-scratch, production-style AWS platform on which the *same* application is deployed two
completely different ways — first on AWS's managed container service, then on a hand-built Kubernetes
cluster — so the two approaches can be compared head-to-head, each running against the same shared
network and database.**

If you're a non-technical reader: think of this repo as a demonstration kitchen. The "food" (the
website) is intentionally plain, because the point isn't the recipe — it's proving, twice over, that
the kitchen itself (the cloud infrastructure, the deployment pipeline, the safety systems) has been
built properly, and that it's possible to swap one entire kitchen for a different one without the
diners ever noticing.

## Origin and objective

This project is the second in a three-part series based on the architecture concepts taught in the
[AWS Solutions Architect SAA-C03 capstone course](https://www.udemy.com/course/aws-solutions-architect-capstone-projects/)
on Udemy. That course builds its infrastructure by hand, clicking through the AWS Console. This
series instead builds the same ideas — and considerably more — as **Infrastructure as Code**: every
resource described in Terraform, every deployment reproducible, every change reviewable as a diff
before it touches anything real. This repository specifically is where that conversion becomes a
**containerised, multi-platform, GitOps-driven** system: one recipe-contest app, deployed first to
AWS ECS/Fargate and then to a self-managed Kubernetes cluster, with a full progressive-delivery
(canary / blue-green / shadow-traffic) exercise running on top of the second platform.

Every document in this repository, including this one, is written with two audiences in mind at
once:

1. **A learning resource.** Someone with no cloud or infrastructure background should be able to read
   any README here and come away understanding *what that piece does and why it exists*, without
   needing to already know Terraform, Kubernetes, or AWS.
2. **A technical demonstration.** Someone evaluating engineering skill should be able to read the same
   documents and see the actual reasoning behind each design decision — not just what was built, but
   the trade-off that was weighed and why it was resolved the way it was.

## How to read this repository

There is a lot here — five independent Terraform layers, four application images, and a slash-command
tool-belt for working the whole thing with an AI pair-programmer. Nobody needs to read all of it in
one sitting. Pick a starting point:

| You are… | Start here |
|---|---|
| A recruiter, or curious about the project generally | Keep reading this page — it's self-contained |
| Interested in the applications themselves (frontend/backend code) | [`apps/`](#the-applications-v1-vs-v2) below |
| A platform/cloud engineer, interested in the infrastructure | [`infrastructure/`](#the-five-infrastructure-layers) below, read the five layers in order |
| Curious how this was built *with* an AI coding assistant | [`.claude/README.md`](.claude/README.md) and [`CLAUDE.md`](CLAUDE.md) |

## The shape of the project

The repository is organised into three top-level concerns:

```
apps/                What runs — the four container images (two competing implementations)
infrastructure/       Where it runs — five independently-deployed Terraform layers
.claude/              How it's built and operated — an AI pair-programmer's guardrails and playbooks
```

The infrastructure is deliberately **not one monolithic Terraform project.** It's five separate
layers, each with its own state file, each only reaching into the others through Terraform data
source lookups (by resource tag) rather than a shared state or a single `terraform apply` for
everything. The practical benefit shows up exactly once, but it's a big one: this project needed to
delete an entire compute platform (ECS) and stand up a completely different one (Kubernetes)
**without touching the network or the database at all.** In a single monolithic deployment, that kind
of platform swap usually means tearing down and rebuilding everything downstream of the change. Here,
it means running `terraform destroy` in two directories and `terraform apply` in a third.

## The five infrastructure layers

| Layer | Builds | |
|---|---|---|
| [`01-aws-vpc`](infrastructure/01-aws-vpc/README.md) | The network: a VPC, subnets across three Availability Zones, and the one public load balancer every later layer shares. | Always on |
| [`02-aws-rds`](infrastructure/02-aws-rds/README.md) | One shared, Multi-AZ MySQL database, with credentials that rotate themselves automatically. | Always on |
| [`03-aws-ecr`](infrastructure/03-aws-ecr/README.md) | A private container registry, plus GitHub Actions CI that authenticates with no stored AWS password. | ECS phase |
| [`04-aws-ecs`](infrastructure/04-aws-ecs/README.md) | The application running on AWS Fargate, behind its own internal load balancer. | ECS phase |
| [`05-aws-k8s`](infrastructure/05-aws-k8s/README.md) | A self-managed Kubernetes cluster (K3s, on plain EC2) running an Istio service mesh and an ArgoCD GitOps pipeline — where **both** application versions run side by side. | Kubernetes phase |

Laid out by deploy order — including the one-time platform swap in the middle — the sequence is:

```
01-vpc → 02-rds → 03-ecr → 04-ecs → [destroy 03 & 04] → 05-k8s
```

01 and 02 are the permanent foundation — the network and the database — and they stay up the whole
time. The ECS phase (03 + 04) and the Kubernetes phase (05) are never deployed at once: once the ECS
build has been exercised and compared, layers 3 and 4 are destroyed — specifically to stop paying for
a compute platform that has done its job — *before* layer 5 is deployed, so the two never contend for
the shared load balancer. Layer 5 then inherits the *exact same* ALB (from layer 1) and database
(from layer 2) that the two permanent layers have been holding up all along — which is precisely why
those were carved out as their own standalone layers to begin with. (A high-level design sketch lives
at `infrastructure/01-aws-vpc/documents/RR-HLD-V2.png`, but the implementation moved past it in
places — most notably the Kubernetes data path, which differs from what that diagram shows; the ASCII
traffic-path diagrams inside each layer's own README describe what was actually built.)

## The applications: v1 vs v2

`apps/` holds two independent implementations of the same recipe-contest application — a frontend and
a backend each — built specifically so they can be compared under live, shifting traffic rather than
just read side by side as code.

| | v1 (baseline) | v2 (challenger) |
|---|---|---|
| Frontend | [Next.js](apps/v1-frontend-nextjs/README.md) — server-rendered, fetches data before the page is sent | [Vite + React](apps/v2-frontend-vite/README.md) — a client-side SPA, fetches after the page loads |
| Backend | [Flask](apps/v1-backend-flask/README-1.md) — Python, `mysql-connector` pooling | [Go](apps/v2-backend-go/README.md) — native `net/http` and `database/sql` |
| Runs on | **Both** ECS (layer 4) and Kubernetes (layer 5) — one image, two platforms | Kubernetes (layer 5) **only** — purpose-built for the traffic-shifting exercises |

Both backends talk to the identical database from layer 2, which is what makes a live comparison
meaningful in the first place: v1 and v2 are always being judged against the same data, not separate
copies of it. The two pairs also differ in a way that's easy to miss but matters a lot in practice —
v1's Flask health check is shallow enough to serve as both its liveness and readiness probe, while
v2's Go health check genuinely queries the database, which means it *must* be split into a separate
shallow endpoint for liveness. Get that backwards and a routine database failover turns into a
fleet-wide crash loop. It's covered in depth in the [Go backend's README](apps/v2-backend-go/README.md)
because it's the single most safety-critical design decision anywhere in this project.

## The central demonstration: progressive delivery with Istio

Layer 5 is where this project's actual thesis gets tested: with both application versions running
simultaneously behind an Istio service mesh, real traffic can be shifted between v1 and v2 using
every major technique a production team would reach for —

- **Canary** — gradually shifting a small, then growing, percentage of new sessions to v2 (10% → 50%
  → 90% → …), watching error rate and latency at each step before going further.
- **Blue-green** — cutting every new session over to v2 in one step rather than gradually.
- **Shadow (traffic mirroring)** — silently duplicating real, live backend requests to v2 without
  ever showing its response to a user, so the challenger can be exercised under genuine production
  traffic before it's trusted with a single real one.

All three are the same underlying Istio primitive — a weighted (or mirrored) traffic rule — used
differently, and all three are watched through the same observability stack: a live Kiali mesh graph
for "is this actually happening right now," and a Grafana Cloud dashboard, colour-coded by version,
for the longer-term view. The full mechanism — including the cookie-based session stickiness that
keeps one browser tab from flapping between two visually different frontends mid-session — is
documented in [`infrastructure/05-aws-k8s/README.md`](infrastructure/05-aws-k8s/README.md).

## Engineering themes that repeat across every layer

A few decisions show up, in slightly different clothes, in nearly every layer of this project. They're
worth naming once here, because seeing the same principle applied five times in five different
contexts is more telling than any single instance of it.

- **Security.** No AWS credential is ever stored as a GitHub secret — CI authenticates to AWS via
  OpenID Connect federation instead (see [layer 3](infrastructure/03-aws-ecr/README.md)). Internal
  traffic is chained security-group-to-security-group rather than by IP range: every hop, from the
  public load balancer down to the database, authorises the *specific* security group allowed to reach
  it, so a rule never trusts a raw CIDR block where naming the source directly would do (the only
  deliberately broad `0.0.0.0/0` ranges are the unavoidable ones — the public ALB accepting the
  internet, and the cluster nodes' outbound path for pulling images). IAM roles are split by *need*,
  not convenience: on ECS the frontend task is granted no AWS permissions at all — it has no reason to
  touch an AWS API — and on Kubernetes only the backend worker nodes, never the frontend ones, can
  read the database secret (see [layer 4](infrastructure/04-aws-ecs/README.md) and
  [layer 5](infrastructure/05-aws-k8s/README.md)). Database credentials themselves are never an
  environment variable — only a Secrets Manager ARN is, and the actual secret rotates itself
  automatically on a schedule (see [layer 2](infrastructure/02-aws-rds/README.md)).
- **Reliability.** The database runs Multi-AZ, meaning a failover is a routine, survivable event
  rather than an incident. That single fact is the reason this project cares so much about the
  difference between a *shallow* health check (proves a process is alive) and a *deep* one (proves a
  dependency is reachable) — wiring the wrong one to liveness turns a 60–120 second database blip into
  a self-inflicted, fleet-wide outage. This exact lesson appears, and is fixed, in three different
  places: the [Flask backend](apps/v1-backend-flask/README-1.md), the
  [Go backend](apps/v2-backend-go/README.md), and the [Kubernetes manifests](infrastructure/05-aws-k8s/README.md)
  that wire the probes in.
- **Cost discipline.** Layers are destroyed the moment they've served their purpose (ECR and ECS,
  once the Kubernetes comparison is ready to begin) rather than left running "just in case." A NAT
  gateway — one of the more easily-forgotten recurring AWS costs — exists in exactly one layer, because
  it's the only layer with genuine internet egress it can't avoid (pulling images from GitHub's
  container registry); every other layer reaches AWS services through private VPC endpoints instead.
  Istio's sidecar proxies are capped to a fraction of their default memory footprint so the four
  application Deployments — eight pods in all, each running its own Envoy sidecar alongside the app
  container — fit across two small (t3.medium) worker nodes. A per-layer cost breakdown is wired
  up via Infracost (`infracost-config.yml`, `extract_all_costs.sh` at the repo root) — see the
  `finops-engineer` entry in [`.claude/README.md`](.claude/README.md) for how that tooling is kept
  accurate as the Terraform changes.
- **GitOps and determinism.** Every image is tagged with its exact git commit SHA, and CI writes that
  SHA back into the Kubernetes manifests itself — so ArgoCD's job is never "guess what changed," and a
  rollback is a plain `git revert`, not a manual production incident. See
  [`infrastructure/05-aws-k8s/README.md`](infrastructure/05-aws-k8s/README.md) for the full pipeline.

## Built with an AI pair-programmer, deliberately fenced in

Alongside the application and infrastructure code, this repository also documents *how it was built*:
`CLAUDE.md` is the project brief an AI coding assistant (Claude Code) loads automatically at the start
of every session — architecture, prior incidents, and the current state of the work. `RUNBOOK.md` and
`prompt.md` are the operational companions: the procedure for driving a session, and a kickoff prompt
used for one specific debugging exercise. `.claude/settings.json` and the six specialist subagents
under `.claude/agents/` are the actual safety mechanism — a tiered permission system that lets the
assistant freely inspect the account and the cluster, but never apply, deploy, or push anything
without a human approving that specific action first. The reasoning behind that whole setup —
including *why* a fix is always proposed as a diff and never applied silently — is written up in
[`.claude/README.md`](.claude/README.md).

One small detail worth pointing out: the documentation style used across every README in this
project — including this one — was set by a single hand-written draft for the Flask backend. That
original draft is still there, unedited, at `apps/v1-backend-flask/README.md`; the complete version
that followed its lead is [`apps/v1-backend-flask/README-1.md`](apps/v1-backend-flask/README-1.md).

## Full repository map

```
apps/
├── v1-frontend-nextjs/    → README.md            Next.js — the baseline frontend
├── v1-backend-flask/      → README.md            (original draft — the style model for this whole repo)
│                          → README-1.md          (the complete write-up)
├── v2-frontend-vite/      → README.md            Vite + React — the challenger frontend
└── v2-backend-go/         → README.md            Go — the challenger backend

infrastructure/
├── 01-aws-vpc/            → README.md            Network + shared public ALB
├── 02-aws-rds/            → README.md            Multi-AZ MySQL + automatic secret rotation
├── 03-aws-ecr/            → README.md            Container registry + passwordless CI
├── 04-aws-ecs/            → README.md            Fargate services + internal ALB
└── 05-aws-k8s/            → README.md            Self-managed K3s + Istio + ArgoCD

.claude/                   → README.md            Permission model, subagents, slash commands
CLAUDE.md                                          Auto-loaded project brief (architecture + history)
RUNBOOK.md                                         Procedure for working this repo with Claude Code
prompt.md                                          A one-off kickoff prompt (K8s networking debugging)
.github/workflows/         → README.md            The two CI/CD pipelines (ECR-era and GHCR/GitOps-era)
```

## Where this sits in the wider series

This is **Part 2** of a three-part series built around the same fictitious company and recipe-contest
brief — and it's the part named *"Containerised"* for a reason: it's where the architecture becomes
container-based and multi-platform. The series as a whole rebuilds a console-driven AWS reference
architecture (the SAA-C03 capstone course referenced above) as Terraform Infrastructure as Code. This
README, and the ten it links to, describe only what actually exists in *this* repository — nothing
from the other parts is assumed or duplicated here.
