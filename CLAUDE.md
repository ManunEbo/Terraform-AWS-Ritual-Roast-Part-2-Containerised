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
- Duplicate `metadata:` bug in all 4 pod templates fixed — labels and annotations merged into single block ✓
- Kiali chart corrected: `kiali-operator v2.28.0` (not `kiali-server`); Prometheus chart: `29.13.1` ✓

**Bootstrap bugs found and fixed 2026-07-01 (CRITICAL — these caused two failed deploys):**

**Bug 1 — `node-role.kubernetes.io/worker=true` in `--node-labels` (commit `922621f`)**
- Kubelet v1.28 rejects `kubernetes.io` labels at registration time unless they match an explicit
  allowlist (`kubelet.kubernetes.io`, `node.kubernetes.io` prefixes, or specific beta/topology labels).
  `node-role.kubernetes.io/worker` is NOT in that set → kubelet exits on every start attempt →
  workers join the API server but can never become Ready.
- **Fix:** Removed `--node-label node-role.kubernetes.io/worker=true` from both worker user_data scripts.
  Apply the cosmetic role label POST-JOIN via `kubectl label node <name> node-role.kubernetes.io/worker=worker`.

**Bug 2 — Calico CRD wait timeout (120s) aborts bootstrap (commit `a63eebb`)**
- `user_data_cp.sh` runs `kubectl wait --for=condition=Established crd/installations.operator.tigera.io
  --timeout=120s` immediately after applying `tigera-operator.yaml`. On a freshly-booted leader under
  load, the CRD establishment takes >120s → `set -e` kills the script → `custom-resources.yaml` is never
  applied → tigera-operator runs indefinitely with "Installation config not found" → no pod network →
  coredns/metrics-server stay Pending → ArgoCD Helm install never starts → no namespaces, no secrets,
  no apps. The cluster appears running (nodes join) but is completely unbootstrapped.
- **Fix:** Added `sleep 30` after applying `tigera-operator.yaml` (lets API server register CRDs before
  polling), increased timeout to 300s. Both committed and pushed.
- **Live recovery (if it happens again):** `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml` then continue manual bootstrap below.

**ACTIVE — Phase 2 (canary/blue-green/shadow):**
- v2 pods not yet running; pending ArgoCD bootstrap completion and sync of `ritual-roast-canary`
- Istio traffic weights currently 100% v1 / 0% v2 (steady state in `dev-apps/routing/istio-routing.yml`)
- Prometheus (in-cluster) and Kiali (operator) committed and pushed ✓

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

## SESSION HANDOVER — 2026-07-01 END-OF-DAY

### Access constraints (critical — read first)
- **No local `kubectl`** on the dev machine. Cluster access is **SSM only** to the EC2 nodes.
- **Repo is private (SSH remote)** — raw GitHub URLs 404, and `kubectl apply -f <github-url>` won't work.
- **All cluster changes must go via git commit + push → ArgoCD syncs.** No exceptions.

### All commits on main (pushed)
| Commit | What it does |
|---|---|
| `922621f` | Remove `node-role.kubernetes.io/worker=true` from worker user_data — kubelet blocks this label at registration |
| `a63eebb` | Increase Calico CRD wait 120s→300s + add 30s pre-sleep to prevent bootstrap abort on loaded node |
| (earlier) | Sidecar memory cap, Prometheus, Kiali, canary staging, kiali-routing, metadata merge fix |

### Cluster state at end of session
- **Nodes:** 5 nodes (3 CP + 2 workers), all Running. Workers: `ip-10-16-121-80` (one role) and `ip-10-16-124-222` (other role).
- **Calico:** Fully up — manually applied `custom-resources.yaml` after Bug 2 abort. All calico-node pods Running.
- **Worker role labels:** NOT YET APPLIED. After deploy, run from any CP node:
  ```bash
  kubectl label node <worker-1-hostname> node-role.kubernetes.io/worker=worker
  kubectl label node <worker-2-hostname> node-role.kubernetes.io/worker=worker
  ```
- **ArgoCD: NOT INSTALLED.** Bootstrap aborted at the Calico CRD wait step. The session ended mid-recovery.

### Recommended first action tomorrow

**Destroy and redeploy cleanly.** Both bugs are fixed and committed. A fresh `terraform apply` will now
bootstrap end-to-end without manual intervention. Do not attempt to continue the half-bootstrapped
cluster — it's missing ArgoCD, all namespaces, all secrets.

```bash
cd infrastructure/05-aws-k8s
terraform destroy -auto-approve    # confirm in AWS console it's gone
terraform apply                    # fresh deploy with both fixes in
```

Expected timeline after apply: ~20 min to full ArgoCD sync (Calico 3 min, ArgoCD 5 min, Istio + apps 10 min).

### If you want to skip destroy and finish the manual bootstrap instead

The cluster has Calico but nothing else. SSM into any CP node and run these in order:

```bash
# 1. Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v3.14.4 bash

# 2. ArgoCD
kubectl create namespace argocd || true
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --version 7.3.11 --set server.service.type=ClusterIP

# 3. GitHub PAT → ArgoCD repo secret
GITHUB_PAT=$(aws secretsmanager get-secret-value --region eu-west-2 \
  --secret-id rr-dev-argocd-github-token --query SecretString --output text)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ritual-roast-git-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised.git
  password: $GITHUB_PAT
EOF

# 4. dev namespace + Istio injection label + GHCR pull secret
kubectl create namespace dev || true
kubectl label namespace dev istio-injection=enabled --overwrite
kubectl create secret docker-registry ghcr-login-secret \
  --namespace=dev --docker-server=ghcr.io \
  --docker-username=ManunEbo --docker-password=$GITHUB_PAT || true

# 5. backend-config ConfigMap — get DB_SECRET_ARN first:
aws secretsmanager list-secrets --region eu-west-2 \
  --query "SecretList[?contains(Name,'rr-dev')].{Name:Name,ARN:ARN}" --output table
# Then apply (replace ARN with the RDS credentials secret ARN from above):
DB_SECRET_ARN="arn:aws:secretsmanager:eu-west-2:ACCOUNT:secret:rr-dev-rds-XXXXX"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: dev
data:
  SECRET_ARN: "$DB_SECRET_ARN"
  AWS_REGION: "eu-west-2"
EOF

# 6. observability namespace + Grafana credentials secret
kubectl create namespace observability || true
GRAFANA_TOKEN=$(aws secretsmanager get-secret-value --region eu-west-2 \
  --secret-id rr-dev-grafana-cloud-token --query SecretString --output text)
GRAFANA_URL=$(aws secretsmanager get-secret-value --region eu-west-2 \
  --secret-id rr-dev-grafana-remote-write-url --query SecretString --output text)
GRAFANA_ID=$(aws secretsmanager get-secret-value --region eu-west-2 \
  --secret-id rr-dev-grafana-instance-id --query SecretString --output text)
kubectl create secret generic grafana-auth --namespace=observability \
  --from-literal=bearer-token=$GRAFANA_TOKEN \
  --from-literal=remote-write-url=$GRAFANA_URL \
  --from-literal=instance-id=$GRAFANA_ID || true

# 7. Wait for ArgoCD CRD then fire root Application
until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do sleep 5; done
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-observability
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised.git'
    targetRevision: main
    path: infrastructure/05-aws-k8s/k8s-manifests/observability
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: observability
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

After step 7, watch ArgoCD pick up and sync everything:
```bash
kubectl -n argocd get applications -w
```

### What ArgoCD will deploy (sync-wave order)
```
Wave -1 : istio-base             (Istio CRDs)
Wave  0 : alloy ConfigMap + RBAC
Wave  1 : istiod  |  prometheus  (in-cluster Prometheus for Kiali)
Wave  2 : istio-ingressgateway   |  kiali (kiali-operator)
Wave  3 : ritual-roast-workloads (v1 apps)  |  ritual-roast-canary (v2 at 0%)
Wave  4 : grafana-alloy DaemonSet
```

### Post-deploy verification
```bash
kubectl get nodes                          # all 5 Ready
kubectl -n argocd get applications         # all Synced/Healthy
kubectl -n dev get pods                    # v1 pods 2/2, v2 pods 2/2
kubectl -n observability get svc kiali     # kiali service exists
# Then in browser: http://<ALB-DNS>        website working
# And:            http://<ALB-DNS>/kiali   Kiali mesh graph
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
