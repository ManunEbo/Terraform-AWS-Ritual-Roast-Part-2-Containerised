# CLAUDE.md — Ritual Roast Infrastructure (MAIN REPO)

> Claude Code loads this file automatically at the start of every session in this repo.
> It shapes how Claude *behaves*; it does NOT enforce anything — the hard guardrails live in
> `.claude/settings.json`. Keep both in sync.

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

v2 is the **challenger** (v1 = base). The v2 deployments and all Istio routing manifests are built
and committed. See SESSION HANDOVER for current canary status and how to step through each strategy.

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

## Current findings — verified 2026-07-01

**CLEARED (do not re-litigate):**
- K3s pinned to `v1.28.15+k3s1` on all install lines (CP + both worker user_data scripts) ✓
- `dev` namespace has `istio-injection=enabled` — all app pods are 2/2 with Envoy sidecars ✓
- istiod has `nodeSelector: tier: frontend`, toleration, and resource caps (100m/128Mi req, 500m/512Mi lim) ✓
- `deploy-ecs.yml` renamed to `deploy-ecs.yml.disabled` ✓
- v1 probes correct (single `/health` endpoint for both liveness + readiness) ✓
- v2 `/livez` present in `apps/v2-backend-go/main.go`; split-probe contract wired in v2 deployment ✓
- ArgoCD Application `path:` values include `infrastructure/` prefix — correct, do NOT strip ✓
- Security groups, ALB health check, NAT coverage, CIDR overlap, Gateway selector — all clear ✓
- SHA write-back job present in `deploy-ghcr-k8s.yml` ✓

**ACTIVE — Phase 2 (canary/blue-green/shadow):**
- v2 pods not yet running; pending ArgoCD sync of `ritual-roast-canary` Application
- Istio traffic weights currently 100% v1 / 0% v2 (steady state in `dev-apps/routing/istio-routing.yml`)
- Prometheus (in-cluster) and Kiali (operator) committed; last version-fix commit not yet pushed — see handover

**Node capacity — resolved:**
- Istio default sidecar memory limit (1024Mi) capped to 128Mi via pod annotations on all 4 deployments
- Prometheus and Kiali steered to CP nodes via `nodeAffinity` preference

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

---

## SESSION HANDOVER — 2026-07-01 (read this before doing anything)

### Access constraints (critical — read first)
- **No local `kubectl`** on the dev machine. Cluster access is **SSM only** to the EC2 nodes.
- **Repo is private (SSH remote)** — raw GitHub URLs 404, and `kubectl apply -f <github-url>` won't work.
- **All cluster changes must go via git commit + push → ArgoCD syncs.** No exceptions.

### Phase 1 status — COMPLETE ✓
Website is live and healthy:
- K3s v1.28.15+k3s1, 3 CP + 2 workers (all t3.medium), Calico 3.26.1 — all nodes Ready
- istiod 1.30.1 ✓ | istio-ingressgateway ✓ | All app pods 2/2 (Envoy sidecars injected)
- v1-frontend-nextjs: 2/2 Running ✓
- v1-backend-flask: 2/2 Running ✓ (boto3 timeouts + startupProbe fixed)
- Grafana Alloy: Running on all 5 nodes, remote-writing to Grafana Cloud ✓
- Website accessible at `http://<ALB-DNS>` — data send/retrieve confirmed working

### Phase 2 status — IN PROGRESS

#### What's committed and pushed
| Commit | What it does |
|---|---|
| `3820001` | Sidecar memory limits capped to 128Mi on all 4 deployments; Prometheus + Kiali nodeAffinity to CP nodes |
| `3820001` | `canary-staging-app.yml` — ArgoCD Application for v2 pods (0% traffic) |
| `3820001` | `prometheus-app.yml` — in-cluster Prometheus for Kiali (chart v29.13.1, 2h retention) |
| `3820001` | `kiali-app.yml` — Kiali via operator (chart kiali-operator v2.28.0, anonymous auth) |
| `3820001` | `kiali-routing.yml` — VirtualService: `http://<ALB-DNS>/kiali` → Kiali pod |

#### What's committed but NOT YET PUSHED
| Commit | What it does |
|---|---|
| `97025ca` | Fix kiali chart: `kiali-server` → `kiali-operator v2.28.0`; prometheus: `25.27.0` → `29.13.1` |

**First action this session:**
```bash
git push --set-upstream origin main
```

#### What ArgoCD will do after push (new sync-wave order)
```
Wave -1 : istio-base             ✓ already Synced/Healthy
Wave  0 : alloy ConfigMap + RBAC (instant Healthy)
Wave  1 : istiod  ✓  |  prometheus (new — in-cluster Prometheus for Kiali)
Wave  2 : istio-ingressgateway ✓  |  kiali (new — kiali-operator)
Wave  3 : ritual-roast-workloads ✓  |  ritual-roast-canary (new — v2 pods at 0% traffic)
Wave  4 : grafana-alloy DaemonSet ✓
```

#### Verify after push
From SSM session on any cluster node:
```bash
# New applications should appear
kubectl -n argocd get applications

# v2 pods should come up 2/2 once ritual-roast-canary syncs
kubectl -n dev get pods -l version=v2 -w

# Kiali service (operator creates this — VirtualService points to it)
kubectl -n observability get svc kiali

# Access Kiali
http://<ALB-DNS>/kiali
```

### Observability stack

| Component | Purpose | Where |
|---|---|---|
| Grafana Alloy | Scrapes Envoy sidecars + nodes → remote-writes to Grafana Cloud | `observability` ns, DaemonSet on all 5 nodes |
| In-cluster Prometheus | Scrapes Istio metrics for Kiali's live graph only (2h retention, no PV) | `observability` ns, prefers CP node |
| Kiali | Live service mesh graph, traffic animation, VirtualService viewer | `observability` ns, prefers CP node |
| Grafana Cloud | Long-term metrics, dashboards, alerting | External (remote-write target) |

**Kiali access:** `http://<ALB-DNS>/kiali` — anonymous, no login.
**Kiali Graph settings:** Namespace=dev → Versioned app graph → enable Traffic Animation + Traffic Distribution.

### Canary strategy — GitOps only

All traffic weight changes happen by editing `dev-apps/routing/istio-routing.yml` and pushing.
ArgoCD applies the change within ~3 minutes. No `kubectl apply` needed.

The `canary-variants/` files are **reference templates** — they show the target weights for each step.
Do NOT put them in `dev-apps/routing/` (same VirtualService name → collision under recursive sync).
Instead, copy the weight values from the variant file into `istio-routing.yml`, commit, push.

#### Canary step sequence
| Step | Frontend weights (v1/v2) | Backend weights (v1/v2) | Verify in Kiali |
|---|---|---|---|
| Baseline (current) | 100 / 0 | 100 / 0 | All traffic on v1 |
| Canary 10% | 90 / 10 | 90 / 10 | Thin v2 line, error rate stable |
| 30% | 70 / 30 | 70 / 30 | Line thickens |
| 50% | 50 / 50 | 50 / 50 | Equal split |
| 70% | 30 / 70 | 30 / 70 | v2 dominant |
| 90% | 10 / 90 | 10 / 90 | Near full cutover |
| Blue-green (100% v2) | 0 / 100 | 0 / 100 | v1 nodes go grey |
| Rollback | `git revert` the weight commit | ArgoCD re-applies v1 weights |

#### Shadow mode (backend only)
To mirror GET reads to v2 without affecting users, copy the `mirror:` spec from
`canary-variants/vs-backend-shadow.yml` into the `backend-route` VirtualService in `istio-routing.yml`.
**Critical:** mirror is GET-only (no POST mirror) — mirroring writes would double-insert rows in the
shared RDS. v2's mirrored responses are discarded; users only see v1.
In Kiali Graph: v2 backend node shows inbound traffic despite 0% weight — confirms mirror is working.

### Node memory budget (post-fix)

All nodes are t3.medium (4096 MiB). After sidecar limit cap:

| Node | Total limits | % of RAM | Safe? |
|---|---|---|---|
| Frontend worker | ~3200 MiB | 78% | ✓ |
| Backend worker | ~2432 MiB | 59% | ✓ |

Sidecar limit is 128 MiB (was 1024 MiB default). Actual Envoy usage ~50–80 MiB under normal load.
Prometheus (256 MiB limit) and Kiali (256 MiB limit) land on CP nodes via nodeAffinity preference.
