# CLAUDE.md — Ritual Roast Infrastructure (MAIN REPO)

> Claude Code loads this file automatically at the start of every session in this repo.
> It shapes how Claude *behaves*; it does NOT enforce anything — the hard guardrails live in
> `.claude/settings.json`. Keep both in sync.
>
> ⚠️ **SEED — paths corrected for THIS repo; FINDINGS not yet re-derived.** The architecture,
> contracts (data path, probe contract, image/GitOps strategy) and paths below are correct for this
> repo: the five Terraform layers live under **`infrastructure/`**; `apps/` and `.github/workflows/`
> are at the repo root. The **"Current findings"** section is a PLACEHOLDER — run `/audit` against this
> repo and populate it from what the files actually say. Do NOT import the sandbox's "already fixed on
> disk" status: this repo is likely still original. The sandbox checklist (in HANDOFF.md) is a guide to
> what to look for, not a statement of this repo's state.

## What this project is

Infrastructure-as-code for **Ritual Roast**, deployed to **AWS** with **Terraform**, as a **five-layer
monorepo deployed sequentially**. All five layers live under **`infrastructure/`**; `apps/` and
`.github/workflows/` are at the repo root.

1. `infrastructure/01-aws-vpc` — VPC, subnets (public / private-app / private-data across
   eu-west-2a/2b), routing, gateways, the shared **public ALB** (port-80 listener, default action =
   404 fixed-response), VPC endpoints. VPC CIDR is **10.16.0.0/16**.
2. `infrastructure/02-aws-rds` — shared **RDS MySQL** (Multi-AZ), Secrets Manager + a Lambda rotation
   fn, IAM.
3. `infrastructure/03-aws-ecr` — ECR registry + IAM; images built/pushed via GitHub workflows.
4. `infrastructure/04-aws-ecs` — ECS/Fargate frontend + backend, an internal ALB, its own ALB listener
   rule (priority 100, `/*`) and target group.
5. **Destroy 03 & 04** (cost saving in dev), then deploy:
6. `infrastructure/05-aws-k8s` — self-managed **K3s** (HA, embedded etcd) on EC2, **Calico** CNI,
   **Istio** mesh, **ArgoCD** GitOps. Pulls images from **ghcr.io**.

`apps/` holds **one set of container images** (v1 flask + nextjs, v2 go + vite) reused by BOTH ECS and
K8s. The team uses this to compare canary / blue-green / shadow strategies.

## Critical context for anyone debugging

- **04 (ECS) and 05 (K8s) never run at the same time** — 03/04 are destroyed before 05, so they do NOT
  contend for the shared ALB at runtime. The K8s "100% cutover" listener rule (priority 10, `/*`) is
  leftover-proofing; with ECS gone it is the only rule on the listener.
- **One image, two platforms.** App-code comments may mention ECS/Fargate even on the K8s path
  (`tasks.tf`, "Fargate", "Internal ALB"). These are **shared-image drift, not bugs** — differences
  are injected at runtime (env / ConfigMap).
- `tcp_keepalive=True` in the Flask boto3 config is **platform-neutral** (defeats NAT/endpoint
  idle-drop on both ECS and K8s); it does not require forking the image.

## The real K8s data path (verified in the code; differs from RR-HLD-V2.png)

The diagram shows the ALB path-routing `/api/*` to the backend directly. The implementation does NOT —
that diagram is stale. Actual path:

`Internet -> ALB:80 (rule /* ) -> target group :30080 -> frontend node -> kube-proxy ->
istio-ingressgateway pod :80 -> Gateway/VirtualService -> rr-frontend-nextjs-svc -> Next.js pod :3000`

The Next.js frontend then calls the backend **internally, server-side** (`'use server'`,
`BACKEND_URL=http://rr-backend-flask-svc:80`) -> Flask :5000 -> RDS :3306 (+ Secrets Manager via VPC
endpoint). The **NLB is the K3s API load balancer (6443)** for node joins — NOT app ingress.

## Probes & the v1/v2 health-endpoint contract (load-bearing — read before wiring any v2 probe)

- **v1 (Flask backend, Next.js frontend):** `/health` (Flask) and `/api/health` (Next.js) are
  **shallow** — 200 without touching the DB. v1 can safely use one endpoint for BOTH readiness and
  liveness.
- **v2 (Go backend):** `/health` is **deep** — it runs `db.Ping()`. It must be **readiness only**.
  Liveness must hit the shallow **`/livez`** (200 without touching the DB), added to
  `apps/v2-backend-go/main.go`.

**Rule when writing v2 manifests:** do NOT copy the v1 single-endpoint probe block. Use split
endpoints — `/livez` (shallow) for **liveness**, `/health` (deep) for **readiness**. A DB-touching
liveness probe restart-loops the pod on any RDS blip; this RDS is **Multi-AZ**, so a routine failover
(~60–120s of connection unavailability) would crash-loop the whole backend fleet and keep it down even
after the DB recovers — the "container assassination" failure mode.

v2 is the **challenger** (v1 = base). The v2 deployments plus Istio canary / blue-green / shadow
routing (DestinationRule subsets + weighted/mirrored VirtualService) are a **deliberate later
workstream — not yet built.**

## Image tagging & GitOps image promotion (the SHA workflow)

Images are tagged by commit SHA; CI writes the SHA back into the manifests, so ArgoCD auto-deploys and
rollbacks are deterministic.
- **Build:** `.github/workflows/deploy-ghcr-k8s.yml` pushes `:latest` AND `:${{ github.sha }}` per app,
  building only changed apps (via the `detect-changes` paths-filter).
- **Promote (write-back):** a single `update-manifests` job that `needs:` the build jobs rewrites the
  `image:` of each **changed** app to `:${{ github.sha }}` (use `yq`, not `sed`) and commits ONCE
  (avoids parallel-push races). `permissions: contents: write` on that job ONLY. Unchanged apps keep
  their prior SHA (still in GHCR), so a frontend-only push rolls only the frontend. (Alt: re-tag both
  to the same SHA via `buildx imagetools`, never rebuild.)
- **Auto-sync (goal #1):** ArgoCD sees the manifest text change (sha-A -> sha-B) and rolling-updates.
- **Deterministic rollback (goal #2):** `git revert` the manifest commit -> manifest points back at the
  old SHA -> ArgoCD re-pulls that exact image. This is WHY we use CI write-back and NOT ArgoCD Image
  Updater / auto-newest (auto-newest re-pulls forward on revert, breaking rollback).
- **Loop-safe:** builds trigger on `apps/**`; the write-back commits under the manifests path, so a
  manifest commit doesn't re-fire the build.

First-deploy seeding is ONE-TIME: images exist in GHCR before the Layer-5 apply, so seed the manifests
with a real existing SHA (recommended) or `:latest` as a bootstrap the first push converts to a SHA.
Kubernetes does NOT accept wildcard tags (`image:*`).

**MANIFEST PATH (this repo is the source of truth):** manifests live at
**`infrastructure/05-aws-k8s/k8s-manifests/...`** — the `infrastructure/` prefix **IS present in this
repo**. Manifests are NOT injected via user_data; ArgoCD pulls them by the Application `path:`. The
Application `path:` values (in user_data_cp.sh's root apps and `ritual-roast-app.yml`) should already
read `infrastructure/05-aws-k8s/k8s-manifests/...` and therefore be **correct**. **VERIFY** each one
against the tree during `/audit`; **do NOT strip the `infrastructure/` prefix** — stripping was a
*sandbox-only* fix (the sandbox replica had lost the prefix from its directory tree) and would BREAK
sync here (`ComparisonError: app path does not exist`). The Application `path:` and the SHA write-back
target must be identical — both WITH the prefix.

The ECS workflow (`deploy-ecs.yml`) is disabled during the K8s phase by renaming to
`deploy-ecs.yml.disabled` (its Layer-3 OIDC role is destroyed, so it red-X's on every `apps/v1-*` push
otherwise). Re-enable when Layers 3-4 are redeployed. Do not delete it.

## Current findings — POPULATE VIA `/audit` (do not trust sandbox status)

> This section is intentionally empty of conclusions. Run `/audit` and fill it from THIS repo's files,
> each cited by `file:resource`. The sandbox HANDOFF expects the following — but RE-PROVE each here by
> reading the files (do not paste sandbox line numbers; they may differ):
> - K3s installed UNPINNED in the user_data scripts vs Calico 3.26.1 / Istio chart 1.30.1 (version
>   skew — likely the root cause; pin `INSTALL_K3S_VERSION` on ALL install lines).
> - Missing `istio-injection=enabled` on the `dev` namespace (pods 1/1, no sidecars).
> - istiod with no nodeSelector/toleration/resource caps (can starve etcd/ArgoCD on a small box).
> - Duplicate ArgoCD ownership of dev-apps + any self-referential observability app-of-apps.
> - `:latest` image tags under `selfHeal: true` + no `update-manifests` write-back job in
>   `deploy-ghcr-k8s.yml` (rollback is a no-op).
> - `deploy-ecs.yml` still active (not renamed `.disabled`).
> - v1 probes wired into the deployments? v2 `/livez` present in `apps/v2-backend-go/main.go`?
>
> **Likely NOT a finding here (sandbox-only):** the ArgoCD Application `path:` strip. In this repo the
> `infrastructure/` prefix is present — verify the paths are correct, do NOT strip. (See MANIFEST PATH.)
>
> **Re-confirm CLEARED, then don't re-litigate:** security groups (Calico overlay symmetric, 30080 ALB
> path, 6443 API NLB triangle); ALB health check on 30080 `/` matcher 200; NAT route coverage (single
> NAT, shared route table → both AZ subnets get egress; cost/SPOF tradeoff, not a bug); VPC CIDR
> 10.16.0.0/16 vs pod CIDR 192.168.0.0/16 (no overlap); Istio Gateway selector `istio: ingressgateway`;
> `global-bundle.pem` baked into the backend; env injection consistent, no hardcoded secrets.

## How the team works this

Diagnosis is read-only and runs first; fixes propose diffs and stop for approval.
- **`/audit`** — STATIC, offline, file-only (no cluster/AWS). The driver for Phase A. Version skew and
  pod health first, security groups last.
- **`/diagnose`** — LIVE, post-deploy bisection (requires a running cluster; refuses if none).
- **`/fix <area>`** — routes to a fixer that proposes a diff and stops: `platform-engineer`
  (Terraform/AWS/user_data), `k8s-gitops-engineer` (Istio/ArgoCD/probes), `app-build-engineer` (app
  code/Dockerfiles/CI).

**Fix order is dependency-driven:** version alignment FIRST (the cluster must form), THEN Istio/ArgoCD,
THEN app/probes.

## Operating rules

0. **This is the real Ritual Roast repo — work it in two phases (see RUNBOOK).**
   - **Phase A (now): fix the files offline.** Read, find bugs, edit on disk. No AWS, no cost, no
     cluster. Driven by `/audit` + `/fix`. Use `/audit` (static), NOT `/diagnose` (live), until
     deployed.
   - **Phase B (later): deploy once, verify live.** `terraform apply` per the layer sequence, then
     `/diagnose`.
   - **Fixers only ever PROPOSE diffs and STOP** — they never run `terraform apply/destroy`,
     `kubectl apply/delete`, `argocd sync`, `helm upgrade`, `docker push`, or `git push`. Real
     mutations are allowed ONLY as explicit, human-approved steps; `settings.json` gates them all to
     `ask` and denies `-auto-approve`, force-push, and `*.tfstate` reads. Never pipe around the prompt.
1. **Investigate read-only first.** Prove each hop with a positive observation, not an inference.
2. **dev only.** Never target prod. Never widen a security group to `0.0.0.0/0` as a shortcut.
3. **Never edit `*.tfstate` by hand.** Never print secret values.
4. **Cost discipline.** Prefer `infracost diff` before applying (infracost runs are gated and prompt;
   account/billing/upload subcommands are denied). The estimate is
   `infrastructure/01-aws-vpc/environments/dev/ritual_roast_monthly_forecast.pdf`.
5. **Verify and report** after any approved change, with read-only checks.

## Tooling

Terraform (alias may be `tf`), kubectl, istioctl, argocd, AWS CLI, Docker, Helm, Infracost.
