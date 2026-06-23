---
description: Static, OFFLINE pre-deployment audit — finds and prioritizes bugs by reading the files only. No live cluster or AWS account needed. Run this BEFORE tf apply. (The live counterpart is /diagnose, used AFTER deployment.)
argument-hint: (optional) a layer or area to focus on, e.g. "05-aws-k8s istio"
---

ultrathink

Static audit. This is PRE-DEPLOYMENT: there is no live cluster and no AWS account to query yet.
Work ENTIRELY from the files on disk. Do NOT run kubectl, aws, argocd, terraform plan/apply, or
anything that contacts a cluster or AWS — those calls will fail, and that failure tells you nothing.
Offline, file-only analysis: Read, Grep, Glob, and at most offline validators that never touch AWS
or a cluster (terraform validate/fmt, npm run lint/test, go build/vet). Read CLAUDE.md first.

Focus: $ARGUMENTS (if empty, audit the whole 05-aws-k8s path plus the shared apps/ images).

Step 1 — Map. Use the `infra-explorer` subagent to locate every in-scope file across the five
layers and apps/.

Step 2 — Domain findings, read-and-report only (NO diffs yet, NO live calls). Delegate to the three
engineers in REPORT mode; ask each to return findings with `file:resource` references and a one-line
proposed fix direction — not a full diff (that comes later from /fix):
- `platform-engineer` — the K3s <-> Calico <-> Istio version alignment (user_data_cp.sh installs
  K3s unpinned vs Calico 3.26.1 / Istio chart 1.30.1), NAT route coverage across BOTH AZ private
  subnets, and any SG/ALB wiring that is genuinely wrong in the files.
- `k8s-gitops-engineer` — missing `istio-injection=enabled` on the dev namespace, Gateway/
  VirtualService correctness, istiod scheduling, the duplicate ArgoCD owners (`root-dev-apps` in
  user_data_cp.sh plus `ritual-roast-workloads`) and the self-referential observability app-of-apps,
  `:latest` image tags under selfHeal, **and the ArgoCD Application `path:` values — in THIS repo the manifests live at `infrastructure/05-aws-k8s/k8s-manifests/...` (the `infrastructure/` prefix IS present), so the Application paths should already carry that prefix and be correct. VERIFY each `path:` matches the on-disk tree; do NOT strip the prefix (that was a sandbox-only fix). Flag only a genuine mismatch.**
- `app-build-engineer` — ECS-comment drift in app.py / recipeService.ts (one image, no fork),
  tcp_keepalive being platform-neutral, the probe/health-endpoint contract, and whether the backend
  Dockerfile bakes in /app/global-bundle.pem.

Step 3 — Look BEYOND the known list. A fresh read may surface issues we haven't catalogued; do not
assume the known items are the only ones.

Step 4 — Consolidate ONE prioritized report: each finding cited by `file:resource`, ranked by
impact (cluster-won't-form first), each with a one-line fix and the `/fix <area>` that addresses it.
Note what you CLEARED (e.g. the security groups, the gateway selector, the CIDR ranges) so they are
not re-litigated. Change nothing. End with the ordered list of `/fix` commands to run next
(version first, then istio/gitops, then app/probes).
