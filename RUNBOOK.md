# RUNBOOK — Ritual Roast: fix the files, then verify live

Operational guide for working this repo with Claude Code. `CLAUDE.md` holds the *context*
(architecture, findings); this file holds the *procedure* (what to run, in what order).

**The work has two phases, and they use different tools:**

- **Phase A — fix the files (offline, now).** Read the code, find the bugs, edit them on disk.
  No AWS, no cost, no cluster. Driven by **`/audit`** and **`/fix`**.
- **Phase B — deploy & verify (after the files are sound).** One `tf apply`, then prove traffic
  actually flows. Driven by **`/diagnose`**.

Do NOT run `/diagnose` in Phase A — it observes a live cluster, so against an undeployed stack every
`kubectl`/`aws` call just errors. Use `/audit` until you've deployed.

---

## 0. Where the config files live

```
~/v2-ritual-roast/
├── CLAUDE.md                       # auto-loaded project brief (context)
├── RUNBOOK.md                      # this file (procedure)
├── prompt.md                       # paste-in kickoff prompt (optional)
└── .claude/
    ├── settings.json               # permission guardrails (the safety layer)
    ├── commands/                   # things you TYPE as /name
    │   ├── audit.md                # /audit      (Phase A: static, offline)
    │   ├── diagnose.md             # /diagnose   (Phase B: live, post-deploy)
    │   ├── fix.md                  # /fix <area>
    │   ├── plan-infra.md           # /plan-infra
    │   └── sg-audit.md             # /sg-audit
    └── agents/                     # subagents Claude DELEGATES to
        ├── infra-explorer.md
        ├── k8s-network-debugger.md
        ├── platform-engineer.md
        ├── k8s-gitops-engineer.md
        ├── app-build-engineer.md
        └── finops-engineer.md
```

`.claude/` is hidden — `tree` hides it by default, so verify with `tree -a` or `ls -la`.
Strip any Windows download cruft: `find ~/v2-ritual-roast -name '*:Zone.Identifier' -delete`.

---

## 1. Pre-flight

One-time / occasional:
```
cd ~/v2-ritual-roast
claude update          # required at least once for Opus 4.8 (needs v2.1.154+)
```

Start a session and confirm the wiring:
```
claude
/permissions           # confirm allow / ask / deny loaded
/model                 # confirm opusplan (Opus for planning, Sonnet for execution)
/agents                # confirm all 6 agents are registered
/                      # type slash alone to confirm /audit, /diagnose, /fix appear
```

If `/agents` or the commands don't show, you're in the wrong directory or `.claude/` didn't copy.

---

## 2. Phase A — fix the files (offline, no AWS, no cost)

This is the whole job until the code is sound. Nothing here deploys anything.

**Find the bugs:**
```
/audit
```
`/audit` is the static twin of `/diagnose`. It uses `infra-explorer` plus the three engineers in
read-and-report mode to walk the files for the full bug list and emit a prioritized report with
`file:resource` references — **zero** `kubectl`/`aws` calls. (Focus a run with e.g.
`/audit 05-aws-k8s istio`.)

**Fix them, in dependency order:**

| Order | Command | Agent | What it addresses |
|---|---|---|---|
| 1 | `/fix version` | platform-engineer | Pin K3s <-> Calico <-> Istio so the cluster will form (suspected root cause) |
| 2 | `/fix istio` then `/fix gitops` | k8s-gitops-engineer | Sidecar injection on `dev`, istiod resourcing, ArgoCD duplicate/recursive Apps, `:latest` tags |
| 3 | `/fix comments` (+ `/fix images`) | app-build-engineer | Generalize ECS comments (one image, no fork); confirm `tcp_keepalive`; `global-bundle.pem` |
| 4 | `/fix probes` | app-build-engineer -> k8s-gitops-engineer (+ platform-engineer for ECS) | Define health endpoints, then wire readiness/liveness into the manifests |

`/fix cost` (finops-engineer) is independent of this order and can run any time.

**What "approving a fix" means here:** each `/fix` shows a unified diff and stops. When you approve,
Claude **edits the file on disk** — it does NOT deploy. (`terraform apply` happens once, later, in
Phase B.) Review each diff, approve the edit, move to the next area.

Re-run `/audit` after a batch of fixes to confirm the findings are cleared and nothing regressed.
When `/audit` comes back clean (or only with items you've consciously deferred), Phase A is done.

---

## 3. Phase B — deploy once, then verify live

Only after the files are sound:

1. Deploy Layer 5 with the normal Terraform flow (`terraform apply` in `infrastructure/05-aws-k8s/environments/dev`).
   This prompts for your approval — review the plan, then approve.
2. Verify the cluster formed and traffic flows:
```
/diagnose
```
`/diagnose` first checks a cluster is reachable; if not, it sends you back to `/audit`. Once live, it
runs the bisection (curl node:30080 -> pods -> version -> endpoints -> mesh -> ALB health -> SGs last)
and reports the first broken hop. Anything it finds that's a file problem, fix back in Phase A style
(`/fix <area>`), re-apply, and re-verify.

---

## 4. The agents at a glance

Diagnosis/audit (read-only): **infra-explorer** (Haiku, repo map), **k8s-network-debugger** (Opus,
live bisection). Fixers (diff-only, approval-gated): **platform-engineer** (Terraform/AWS/user_data),
**k8s-gitops-engineer** (Istio/ArgoCD/probes), **app-build-engineer** (app code/Dockerfiles),
**finops-engineer** (infracost usage files/config/extraction; can write those files).
`/audit`, `/diagnose`, and `/fix` route to these for you; you can also name one directly.

---

## 5. Safety rules in force

- Phase A is offline and file-only; Phase B's diagnosis is read-only. Fixers **propose diffs and
  stop** — they never `apply`/`delete`/`sync`/`push`. (The finops-engineer may write infracost files,
  gated to `ask`.)
- `terraform plan/apply/destroy`, `kubectl apply/delete`, `argocd sync`, `helm upgrade`, `docker
  push`, `git push` all **prompt**. Auto-approve forms, force-push, and `*.tfstate` reads are
  **denied**.
- **dev only.** Never widen a security group to `0.0.0.0/0`. Never hand-edit `*.tfstate`.
- **infracost** prompts on every run; `auth` / `configure set api_key` / `upload` / `comment` are
  denied, so Claude cannot link or pay for an account.

---

## 6. Quick context (full version in CLAUDE.md)

Deploy order: 01-vpc -> 02-rds -> 03-ecr -> 04-ecs -> **destroy 03 & 04** -> 05-k8s. ECS and K8s
never run together, so they don't contend for the shared ALB. One image per service (ECS/Fargate
comments on the K8s path are drift, not bugs). Real K8s path: ALB:80 (`/*`) -> TG:30080 -> Istio
gateway -> frontend; frontend calls the backend internally; the NLB is the K3s API LB (6443), not
app ingress. Prime suspect: K3s installed unpinned (newest K8s) against Calico 3.26.1 (tested to
~1.28) and Istio 1.30.1. Already cleared: the security groups, the gateway selector, the 30080 health
check, and the CIDR ranges (VPC 10.16.0.0/16 vs pod 192.168.0.0/16 — no overlap). The five Terraform
layers live under `infrastructure/`; `apps/` and `.github/workflows/` are at the repo root.
