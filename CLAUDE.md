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
istio-ingressgateway pod :80 -> Gateway/VirtualService -> rr-frontend-svc -> Next.js pod :3000`

The Next.js frontend then calls the backend **internally, server-side** (`'use server'`,
`BACKEND_URL=http://ritual-roast-backend:5000`) -> Flask :5000 -> RDS :3306 (+ Secrets Manager via VPC
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

**Pre-redeploy audit — verified 2026-07-02 (static, full four-domain pass; verdict: GO for redeploy):**
- Both bootstrap fixes confirmed on disk AND on origin/main (`922621f`, `a63eebb`); working tree clean ✓
- istiod Helm values in `observability/istio-app.yml` are CORRECT as flat/top-level keys. The Istio
  1.30 istiod chart reads `.Values.nodeSelector` / `.Values.tolerations` / `.Values.resources` at the
  TOP level (verified against the release-1.30 chart deployment template — the old `pilot:` scoping is
  gone). Do NOT "fix" them under `pilot:`; that would make them inert. An audit agent flagged this as a
  HIGH bug — it is a FALSE POSITIVE for chart 1.30.x ✓
- Istio 1.30.1 on K8s 1.28.15: outside Istio's official support window (K8s 1.32–1.36) but inside its
  "tested" window (1.27–1.31). Accepted for dev; align versions when next bumping K3s/Calico.
- Seed image SHAs in all 4 deployments (`96d8b078…` ×3, `0ba5fb4e…` ×1) were written by the CI
  write-back bot AFTER the build jobs succeeded (`needs:` gating), so all 4 tags exist in GHCR — no
  first-sync ImagePullBackOff ✓ (paths-filter evaluates the push range; tags use the head SHA)
- Non-blocking hardening backlog (do NOT churn before the redeploy): bounded retries around the
  network steps in user_data_cp.sh (dnf/get-helm/Calico applies/helm repo run under `set -e` with no
  retry); a timeout on the `until kubectl get crd applications.argoproj.io` loop; `--cluster-init` is
  not idempotent if the lowest-IP CP instance is ever replaced (split-brain risk on ASG replacement);
  frontend ASG desired=1 is tight once a 4-pod canary runs (raise to 2 before canary steps); stray
  14 MB committed binary `apps/v2-backend-go/ritual-roast-backend` fires spurious CI builds (git rm +
  gitignore); minor stale comments in v1-frontend deployment (old svc names) — comments only.

**Bug 3 — Calico CrossSubnet on shared subnets → sidecar-injector webhook unreachable → ZERO pods (found live 2026-07-02, 3rd deploy):**
- The 3rd deploy formed the cluster cleanly (Bugs 1 & 2 dead), but `dev` had **zero pods** and
  ArgoCD showed `ritual-roast-workloads`/`ritual-roast-canary`/`istio-ingressgateway` **Synced but
  Degraded**. Proven root cause (live bisection): the upstream Calico `custom-resources.yaml` creates
  the IP pool with `encapsulation: VXLANCrossSubnet`. Multiple K3s nodes share each /20 subnet, so
  Calico sends **same-subnet** pod traffic **unencapsulated** with raw pod-CIDR (192.168.x) src/dst.
  Those packets are (a) dropped by the EC2 **ENI source/dest check** (default = on) and (b) unmatchable
  by security-group **source-SG** rules (pod IPs are invisible to AWS). istiod runs on a frontend
  worker; the K3s apiserver on the CP node **in that same subnet** therefore cannot reach the
  sidecar-injector webhook → `Post ".../inject": context deadline exceeded` → `failurePolicy=Fail`
  **rejects every pod create** → no app pods, and no ingressgateway (`image: auto` also needs the
  injector). Cross-subnet CP nodes reached istiod fine, which is why it looked intermittent.
- **This corrects a prior "CLEARED" line:** the audit cleared SGs/CIDR/overlay but never checked the
  **ENI source/dest check ↔ CrossSubnet-on-shared-subnet interaction**. It is NOT an SG-rule bug.
- **Fix (committed):** `user_data_cp.sh` no longer applies the upstream `custom-resources.yaml`; it
  applies an inline Installation with **`encapsulation: VXLAN` (Always)**, so every pod packet is
  wrapped in a node-IP (10.16.x) outer header on UDP/4789 (which the SGs already permit) and overlay
  IPs never touch the ENI or SG. No SG widening, no source/dest-check dependency.
- **Cannot be hot-patched:** Calico treats a pool's encapsulation as **immutable once created**. The
  tigera operator accepts an Installation edit (`encapsulation: VXLAN`) but will NOT retrofit the
  existing pool (verified live — `installation` shows VXLAN, `ippool` stays CrossSubnet). Must be set
  at pool-creation time → requires a fresh deploy. `--no-source-dest-check` on the live ENIs alone did
  NOT fix it (the SG source-SG matching gap remains), confirming VXLAN Always is the correct lever.

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

## SESSION HANDOVER — 2026-07-03 END-OF-DAY

### Status: CLUSTER FULLY DEPLOYED AND HEALTHY ✓ (supersedes the 2026-06-30 / 07-01 / 07-02 handovers)
The 3rd deploy succeeded end-to-end (Bugs 1–3 all fixed). All 8 ArgoCD apps Synced/Healthy; the site
serves data (v1 + v2 pods 2/2 with sidecars); Kiali reachable at `/kiali`; Grafana Cloud ingesting
(429 cleared). **Canary walkthrough IN PROGRESS** — the user drives, Claude guides. GitOps canary
steps progressed **90/10 → 50/50 → 10/90** (commits `5774932` → `dcb805f` → `2611bbe`). Current
committed + live state: **v1:10 / v2:90 on both tiers** (the "canary 90%" step). Resume at the
**0/100 blue-green step** — see "RESUME HERE — canary walkthrough" below.

**2026-07-04 session:** blue-green (0/100) was exercised live via the manual `canary-variants/`
files (not GitOps) and cleanly rolled back to the 10/90 state above — git was never touched. This
surfaced a significant ArgoCD **app-of-apps self-heal** gotcha — see
"Live manual-edit gotcha: app-of-apps self-heal" right after the resume section below. Read that
before doing ANY manual `kubectl apply`/`kubectl patch` on this cluster. Backend shadow mode was
redone correctly and **confirmed observed live in both Kiali and the Grafana Cloud dashboard**
(v2 backend showed inbound mirrored traffic at 0% official weight) — no snapshots were captured
that pass, so the observation itself is confirmed but not illustrated yet.

**New in the 2026-07-03 session:** a Grafana Cloud dashboard was built and pushed live — see
"Grafana Cloud dashboard" right after the canary resume-point below.

**2026-07-05: transitioning to write-up phase.** The remaining work is producing illustrations
(screenshots of Kiali graphs, Grafana dashboard panels, terminal output) for a written report on
the canary/blue-green/shadow exercise. Expect repeated redeploys of the same steps above purely to
recapture clean screenshots — no new bugs or strategy changes implied by a "redeploy" mention going
forward unless stated. The user is also switching to a different (non-Mac) computer for this phase
— treat the next session as a fresh local environment (no assumed shell history, credentials cache,
or SSM session state) even though the cluster/repo state described here is unchanged.

### Access constraints (critical — read first)
- **No local `kubectl`** on the dev machine. Cluster access is **SSM only** to the EC2 nodes — run
  kubectl on a CP node via `aws ssm send-command` with a `--parameters file://...json` payload (the
  shorthand form chokes on `===` / parens). CP instance IDs change every redeploy; re-query by tag
  `rr-dev-k3s-control-plane`.
- **Repo is private (SSH remote)** — raw GitHub URLs 404, and `kubectl apply -f <github-url>` won't work.
- **All cluster changes must go via git commit + push → ArgoCD syncs.** No exceptions.

### All fixes on main this deploy (pushed)
| Commit | What it does |
|---|---|
| `922621f` | Bug 1: remove `node-role.kubernetes.io/worker=true` from worker user_data (kubelet rejects it) |
| `a63eebb` | Bug 2: Calico CRD wait 120s→300s + 30s pre-sleep (bootstrap abort on loaded leader) |
| `fe6d5fa` | Bug 3: create Calico pool as **VXLAN Always** (not VXLANCrossSubnet). Shared-subnet pod traffic was unencapsulated → dropped by ENI src/dest check + SG source-SG rules → istiod injector webhook unreachable from same-subnet apiserver → zero pods. VXLAN Always wraps every packet in node-IP/UDP-4789 which the SGs already allow. Pool encap is immutable, so must be set at creation (fresh deploy) |
| `bc635d9`→`f084497`→`bf8ef9a` | Kiali `web_port` quoted (int → CR rejected → no server/Service → `/kiali` 503); `ignoreDifferences` for istio webhooks (managedFieldsManagers: `pilot-discovery`) + Kiali CR (jqPathExpressions `.spec` — its loose CRD schema breaks managedFieldsManagers) |
| `9b7c501` | Trim Alloy scrape to `istio_*` only, drop cAdvisor + annotated-pod jobs, 15s→30s interval — clears Grafana Cloud 429 rate-limit |
| `b3e8020` | Move `/kiali` route INTO `frontend-route` as its first http rule + delete standalone `kiali-routing.yml`. Browser 404'd on /kiali while curl got 200: frontend stamps an `x-frontend` cookie; the separate kiali VirtualService merged on the same gateway+host had non-deterministic order, so the frontend cookie rule captured /kiali → frontend 404. A first-position `/kiali` match within one VS is deterministic and wins |
| `5774932` | Canary step 1: frontend + backend weights 90/10 (v1/v2) |
| (earlier) | Sidecar memory cap, Prometheus, Kiali, canary staging, kiali-routing, metadata merge fix |

### Cluster state at end of session
- **Nodes:** 5 Ready (3 CP + 2 workers), K3s v1.28.15+k3s1.
- **Calico:** VXLAN **Always** — verify `kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.vxlanMode}'` → `Always`. All calico pods Running.
- **ArgoCD:** all 8 apps Synced/Healthy (istio-base, istiod, istio-ingressgateway, kiali, prometheus, ritual-roast-workloads, ritual-roast-canary, root-observability).
- **dev:** v1 + v2 frontend/backend all 2/2 with sidecars. Istio routing at **canary 90% step: v1:10 / v2:90** on both tiers (frontend-route rule `[3]`, backend-route rule `[0]`).
- **Observability:** Kiali at `/kiali` (200); in-cluster Prometheus feeds Kiali's graph; Alloy → Grafana Cloud (429 cleared, `istio_*` only). No in-cluster Grafana by design — Grafana is Grafana Cloud (external).
- **Worker role labels:** cosmetic `node-role.kubernetes.io/worker` still not applied (optional). Apply from a CP node: `kubectl label node <worker-hostname> node-role.kubernetes.io/worker=worker`.

### RESUME HERE — canary walkthrough (interactive: user drives, Claude guides)

Mid-walkthrough. Workflow per step: user edits weights in `dev-apps/routing/istio-routing.yml`,
commits + pushes; ArgoCD applies within ~3 min. **Canary steps 90/10 → 50/50 → 10/90 done**
(commits `5774932` → `dcb805f` → `2611bbe`). **Blue-green (0/100) already exercised** live via the
manual `canary-variants/` files on 2026-07-04 and rolled back cleanly to 10/90 — git untouched, so
GitOps state and live state both still read 10/90. **Backend shadow mode redone and CONFIRMED**
(observed live in Kiali graph + Grafana Cloud dashboard — v2 backend showed inbound mirrored
traffic at 0% weight) — no snapshots captured that pass, so re-run again during the write-up phase
to capture illustrations. Remaining to try: blue-green again via pure GitOps (commit 0/100 weights
instead of the manual variant files) and rollback via `git revert`. Full step table below.

**Before any manual `kubectl apply`/`kubectl patch` step (blue-green, shadow) — read
"Live manual-edit gotcha: app-of-apps self-heal" a few sections below.**

**Shadow-mode traffic-sequencing pitfall (found live 2026-07-04, avoided on the confirmed redo):**
the first shadow attempt applied `vs-backend-shadow.yml`, verified the `mirror` config, then rolled
back to `istio-routing.yml` and re-enabled ArgoCD **before** driving any traffic — so the traffic
loops that followed hit the plain 10/90 split, not the mirror, and nothing was actually mirrored
that round. **Drive traffic between apply/verify and rollback, never after.** Also prefer pinning
the v2 cookie directly against the API path over a cookieless root curl:
`curl -H 'Cookie: x-frontend=v2' $ALB/api/get_recipe` guarantees a real backend GET (and therefore a
mirror) on every request, since v2's nginx always proxies that path to the backend — a cookieless
`curl $ALB/` mostly lands on v2 (per current frontend weights), and v2's root response is static
HTML with no server-side backend call, so that pattern only exercises the backend from the minority
of requests landing on v1's SSR path.

**Which numbers to edit** (do NOT touch the `/kiali` rule or the two cookie rules above it):
frontend-route weighted block = http rule **`[3]`** (`weight:` ~line 139 v1 / ~145 v2); backend-route
weighted block = rule **`[0]`** (`weight:` ~line 171 v1 / ~177 v2).

**Verify a change landed** (SSM to a CP node, then `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`):
`kubectl -n dev get virtualservice frontend-route -o jsonpath='{range .spec.http[3].route[*]}{.destination.subset}={.weight} {end}'`
and the same for `backend-route` with `http[0]`. Nudge ArgoCD if it hasn't polled:
`kubectl -n argocd annotate application ritual-roast-workloads argocd.argoproj.io/refresh=hard --overwrite`.

**Driving/observing traffic — the load-bearing lesson (v1 SSR vs v2 SPA):** ALB =
`http://rr-dev-public-alb-1057461043.eu-west-2.elb.amazonaws.com`
- **Frontend split + v1's backend hop:** drive the ROOT cookieless (`curl -s $ALB/` in a loop). v1
  (Next.js) renders **server-side** and calls the backend → v1→backend edge appears. v2 (Vite) serves
  static HTML on `/` — no backend call from curl (correct, not a fault).
- **v2's backend hop:** `/api/get_recipe` is a real endpoint ONLY on **v2** (Vite nginx `location /api/`
  proxies to the backend). v1 Next.js has NO browser `/api/get_recipe` route (only `/api/health`); it
  fetches via a server-side Server Action. So **NEVER curl `/api/get_recipe` cookieless** — ~90% hits
  v1 → **404 → red edges in Kiali** (alarming but just a missing route, not a regression). Exercise
  v2→backend cleanly by pinning the cookie: `curl -H 'Cookie: x-frontend=v2' $ALB/api/get_recipe`.
- **Best for a demo:** an **incognito browser** on the ALB — each version runs its natural path (v1 SSR
  / v2 client-side) with no false 404s and the recipe table populates from RDS.
- Frontend is **cookie-sticky** (`x-frontend=v1|v2`); a normal browser stays on one version. Use fresh
  incognito windows or cookieless curl to see the split. Count served versions:
  `for i in $(seq 1 100); do curl -s -D - -o /dev/null $ALB/; done | grep -oi 'x-frontend=v[12]' | sort | uniq -c`.
- The blue `backend → PassthroughCluster` edge in Kiali = the backend's RDS / Secrets-Manager call
  leaving the mesh. Expected, not an error.

**Shadow mode** (backend only): copy the `mirror:` spec from `canary-variants/vs-backend-shadow.yml`
into `backend-route`. GET-only — NEVER mirror POST (double-inserts into the shared RDS).

### Live manual-edit gotcha: app-of-apps self-heal (found live 2026-07-04, blue-green session)

**Symptom:** During the blue-green walkthrough, `kubectl patch application ritual-roast-workloads
--type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false, ...}}}}'` (and later
`{"automated":null}`) reported success and `kubectl get` confirmed the field was set — but within
~1 second it silently reverted back to `{"prune":true,"selfHeal":true}`, and the manual
`kubectl apply -f vs-*-bluegreen-v2.yml` weight changes got reverted back to the Git-committed
canary weights each time. This looked identical to the ordinary self-heal race the
`canary-variants/README.md` warns about, but disabling `selfHeal` on `ritual-roast-workloads` alone
did not fix it.

**Root cause:** `root-observability` (the bootstrap root Application, sourced from
`k8s-manifests/observability/`) is an **app-of-apps parent** — `ritual-roast-app.yml`,
`canary-staging-app.yml`, `istio-app.yml`, `kiali-app.yml`, `prometheus-app.yml` all define CHILD
`Application` objects that `root-observability` itself treats as managed resources (confirmed live:
`kubectl -n argocd get application root-observability -o jsonpath='{.status.resources[?(@.kind=="Application")]}'`
lists `ritual-roast-workloads`, `ritual-roast-canary`, `istiod`, etc., each `Synced`). Because
`root-observability`'s own `syncPolicy.automated.selfHeal` is `true`, it reverts ANY live drift on a
child Application's spec — including a `kubectl patch` to that child's own `syncPolicy` field —
back to what `ritual-roast-app.yml` declares in Git. Patching the child alone is therefore a no-op
under a live app-of-apps parent: the parent re-heals the child's policy before the next `kubectl
apply` to the actual workload resources can stick.

**Fix / the pattern to follow for ANY manual live edit on this cluster:** disable
`syncPolicy.automated` on the **entire ArgoCD ancestor chain**, parent first, then the child —
not just the Application that directly owns the resource you're editing:
```bash
kubectl -n argocd patch application root-observability --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n argocd patch application ritual-roast-workloads --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
# ...now kubectl apply -f <manual-manifest>.yml sticks...
```
Restore in reverse order (child first, then parent) once done, so the parent doesn't re-heal a
child that's still mid-restore:
```bash
kubectl -n argocd patch application ritual-roast-workloads --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl -n argocd patch application root-observability --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```
`canary-variants/README.md`'s self-heal-off snippet only patches the one target Application and is
therefore **incomplete** on this cluster's topology — extend it with the parent step above before
following it.

### Grafana Cloud dashboard (added 2026-07-03)

A dashboard-as-code JSON + push script now lives at
`infrastructure/05-aws-k8s/k8s-manifests/observability/dashboards/` — see that folder's `README.md` for
full detail. Summary:

- **Files:** `ritual-roast-mesh-dashboard.json` (the dashboard, source of truth — edit this, not the
  Grafana UI), `push-to-grafana.sh` (pushes/updates it via Grafana's `/api/dashboards/import`), `README.md`.
- **Live now:** pushed to `https://curiousquince1187.grafana.net/d/rr-mesh-traffic/...` — request rate,
  observed traffic-share %, error rate, p95 latency (all by `destination_version`), scrape target health,
  and backend→RDS TCP bytes. Colors are fixed: **v1 = green (`#0ca30c`), v2 = red (`#d03b3b`)** across
  every panel.
- **Strategy-agnostic by design:** plots by `destination_version`, not by canary step, so the same
  dashboard reads canary ramps, blue-green cutovers, and shadow-mirrored traffic (v2 shows inbound on the
  traffic-share panel even at 0% official weight) without any changes.
- **Only shows what's scraped:** the `istio_*` family (+ `up`) — no node/cAdvisor metrics, per the
  429-rate-limit trim in `9b7c501`.
- **To push an edit:** `export GRAFANA_URL=https://curiousquince1187.grafana.net`,
  `export GRAFANA_API_TOKEN=<service-account-token>` (a Grafana **instance** Service Account token,
  Editor+ role — NOT the Alloy remote-write token in `rr-dev-grafana-cloud-token`, which is
  metrics:write-only and can't create dashboards), then `./push-to-grafana.sh`. `overwrite:true` + fixed
  `uid: rr-mesh-traffic` means re-running updates the same dashboard.
- **Not yet done (backlog):** p50/p99 latency panels (currently p95 only), a dedicated Grafana folder
  instead of General, alerting rules.

If a **fresh rebuild** is ever needed: `cd infrastructure/05-aws-k8s && terraform destroy && terraform apply`
now bootstraps end-to-end with all three bugs fixed (~20 min to full sync). Do NOT pass `-auto-approve`
(settings.json denies it — confirm interactively). The manual-bootstrap block below is legacy reference
only; it is not needed on a clean deploy.

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

**Grafana Cloud dashboard access:** `https://curiousquince1187.grafana.net/d/rr-mesh-traffic/...` — v1/v2
mesh traffic, strategy-agnostic (canary/blue-green/shadow). Source + push script:
`infrastructure/05-aws-k8s/k8s-manifests/observability/dashboards/` (see its README). v1=green, v2=red,
fixed across every panel.
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
