# `.claude/` — AI Assistant Configuration

This directory doesn't run in production and isn't part of Ritual Roast the application — it
configures **Claude Code**, the AI coding assistant used to build and maintain this repository. If
you've never seen a directory like this before: think of it as a written-down job description and a
set of hard rules for an assistant that has real, tool-using access to this codebase, this AWS
account, and this Kubernetes cluster. The interesting engineering here isn't a feature of the
website — it's the guardrails and specialist workflows that make it safe to let an AI operate on a
real cloud infrastructure project without babysitting every single action it takes.

## What's in this directory

| Path | Purpose |
|---|---|
| `settings.json` | The hard rules — which commands run automatically, which always require a human to approve, and which are refused outright, no matter what. |
| `agents/*.md` | Six specialist sub-assistants, each scoped to one domain (Terraform, Kubernetes/Istio, app code, cost, live network debugging, read-only exploration). |
| `commands/*.md` | Five reusable workflows (`/audit`, `/diagnose`, `/fix`, `/plan-infra`, `/sg-audit`) that orchestrate those specialists in a specific, deliberate order. |

## Why this exists

This project carries real blast radius: a wrong command here doesn't just break a build, it can
destroy a running Kubernetes cluster, apply an unreviewed change to a live AWS account that costs
real money, force-push over shared git history, or cause a secret to be printed into a chat
transcript. `settings.json` is what makes those outcomes *structurally impossible* rather than
relying on the assistant simply choosing not to do them — the same principle as least-privilege IAM
elsewhere in this project (see `infrastructure/02-aws-rds/README.md` and
`infrastructure/03-aws-ecr/README.md` for two AWS-side examples of the same idea), applied to the
tool doing the engineering rather than the infrastructure it's engineering.

---

## `settings.json` — three tiers of trust

Every command the assistant might want to run falls into exactly one of three lists.

### 1. `allow` — read-only, runs without interrupting anyone

```json
"Bash(terraform validate*)", "Bash(terraform show*)", "Bash(terraform state list*)",
"Bash(kubectl get*)", "Bash(kubectl describe*)", "Bash(kubectl logs*)",
"Bash(istioctl analyze*)", "Bash(istioctl proxy-status*)",
"Bash(aws sts get-caller-identity*)", "Bash(aws ec2 describe-*)", "Bash(aws rds describe-*)",
"Bash(npm run lint*)", "Bash(go build*)", "Bash(go test*)"
```

Everything on this list only ever *inspects* state — it cannot change a single resource, file, or
byte in the cluster or the AWS account. Auto-approving this category removes friction from the large
share of work that's genuinely just "let me go check something" (what does this Terraform plan
currently look like, what pods are running, what does this security group actually allow) without
adding any risk, because none of these commands have a destructive form.

### 2. `ask` — anything that changes real state, always stops and asks first

```json
"Bash(terraform apply*)", "Bash(terraform destroy*)", "Bash(kubectl apply*)",
"Bash(kubectl delete*)", "Bash(helm upgrade*)", "Bash(aws secretsmanager *)",
"Bash(docker push*)", "Bash(git push*)", "Bash(infracost*)"
```

Every command here mutates something real: a `terraform apply` can reshape live AWS infrastructure
and change what the account is billed; a `kubectl apply` can take down live traffic; a `git push` is
immediately visible to every other person with access to the repository. None of these are refused —
they're exactly the actions a human running this project actually needs to take — but every single
one pauses for an explicit yes, every time, regardless of how many times the same command was
approved earlier in the same session. Approval is scoped to the one action in front of it, not a
standing blanket permission.

### 3. `deny` — refused outright, no prompt, no override

```json
"Bash(terraform apply* -auto-approve*)", "Bash(terraform destroy* -auto-approve*)",
"Bash(kubectl delete* --all*)", "Bash(git push --force*)", "Bash(git push -f*)",
"Bash(git reset --hard*)", "Bash(git clean -fd*)", "Bash(rm -rf /*)", "Bash(rm -rf ~*)",
"Read(*.tfstate)", "Read(*.tfstate.backup)", "Read(**/.terraform/**)",
"Read(~/.aws/credentials)", "Read(~/.ssh/**)", "Read(**/.env)", "Read(**/.env.*)"
```

A few distinct ideas are bundled into this one list:

- **Closing the "ask" tier's one loophole.** `terraform apply` alone is only `ask` — but
  `-auto-approve` specifically is `deny`, even though it's "the same command with a flag." That flag
  is precisely the one that would skip the human confirmation the `ask` tier exists to enforce, so
  it's denied outright rather than trusted to the same tier as the plain command.
- **Secrets never enter the conversation, even to *read* them.** `*.tfstate` files can contain
  plaintext values (a Terraform state file may embed a resource's actual attributes, including
  secrets, depending on the resource); `.env` files and `~/.aws/credentials` are the conventional
  homes for real credentials. All of them are denied for *reading*, not just editing — the concern
  isn't "the assistant might corrupt this file," it's "the contents of this file should never be
  capable of being quoted back in a chat transcript at all."
- **No undo, no exceptions.** `git push --force`, `git reset --hard`, `rm -rf /`, and
  `kubectl delete --all` share one property: there's no way to recover from them if they run against
  the wrong target. Rather than trusting a human's "yes" in the moment (people approve prompts too
  quickly when they're in a hurry — that's a known failure mode, not a hypothetical one), these are
  refused before a prompt is even shown.

The `"model": "opusplan"` line at the top of the file is a separate concern from all of the above —
it pins which model does the *reasoning* during planning, upstream of any of these gates deciding
what that reasoning is actually allowed to execute.

---

## The subagents — specialists, not generalists

A subagent is a separate invocation of Claude, spun up for one specific sub-task, with its own
narrower tool access and its own written brief — rather than one generalist assistant trying to hold
Terraform, Istio, application code, and cost accounting in its head at the same time. Splitting the
work this way keeps each specialist's context focused on just its domain, and lets its permissions be
scoped down to only what that domain actually needs.

| Agent | Model | Tools | Job |
|---|---|---|---|
| `infra-explorer` | Haiku | Read, Grep, Glob | Pure read-only cartographer — finds files and summarizes how they connect. No Bash at all: it can't run anything, only look. |
| `platform-engineer` | Opus | Read, Grep, Glob, Bash | Terraform / AWS / EC2 user_data fixes — chiefly the K3s↔Calico↔Istio version alignment, NAT coverage, ECS health checks. |
| `k8s-gitops-engineer` | Opus | Read, Grep, Glob, Bash | Istio and ArgoCD wiring — sidecar injection, VirtualServices, duplicate/self-referential Applications, image tags, readiness/liveness probes. |
| `app-build-engineer` | Opus | Read, Grep, Glob, Bash | Application code, Dockerfiles, and the GitHub Actions build/promotion pipeline. |
| `k8s-network-debugger` | Opus | Read, Grep, Glob, Bash | Live bisection of "why isn't traffic flowing" — runs checks in a fixed order (see `/diagnose` below). |
| `finops-engineer` | Sonnet | Read, Grep, Glob, Bash, **Write, Edit** | The one agent trusted to actually write files — but only `infracost-usage.yml`, `infracost-config.yml`, and `extract_all_costs.sh`. Never Terraform, state, secrets, or app code. |

Two things are worth noticing about this table. First, `infra-explorer` runs on the smallest, fastest
model (Haiku) because its job is locating and summarizing files, not deep engineering judgment —
model choice here is matched to task difficulty, not defaulted to the biggest model everywhere.
Second, every agent except `finops-engineer` has **no** `Write` or `Edit` tool at all — it is
*physically incapable* of changing a file, which is a stronger guarantee than an instruction telling
it not to. `finops-engineer` is the sole exception, and even it is fenced to three specific,
low-blast-radius files by its own brief.

Every one of the engineer agents' descriptions ends the same way: *"Proposes diffs; NEVER
applies/pushes/deploys; always stops for approval."* That's a second, independent layer of the same
guarantee `settings.json` enforces at the tool level — even where an agent's tool list would
technically permit a mutating Bash command, its own instructions still tell it to stop and show a
diff instead of running it.

---

## The slash commands — diagnose first, fix second, always as a proposal

The five commands in `commands/` orchestrate the subagents above into a consistent workflow: **look
before touching anything, and separate "here's what's wrong" from "here's the approved fix."**

- **`/audit`** — static and fully offline. Explicitly refuses to run anything that touches a live
  cluster or AWS account (no `kubectl`, no `aws`, no `terraform plan/apply`) — this is the command
  for auditing files before anything has even been deployed, or re-checking after a fix has been
  applied on disk but not yet rolled out. It maps the relevant files with `infra-explorer`, then asks
  the three engineer agents to report findings *only* (no diffs yet), then consolidates everything
  into one report ordered by impact, ending with the sequence of `/fix` commands to run next.
- **`/diagnose`** — the live counterpart. It refuses to run at all if it can't first confirm a
  cluster is actually reachable, specifically so it doesn't produce a report full of misleading
  failures that just mean "nothing is deployed yet." It drives `k8s-network-debugger` through a fixed
  bisection order: two cheap connectivity probes first, then version compatibility, then image
  pulls / NAT routing, then service endpoints, then the Istio mesh, then ALB target health, and
  **security groups last.** That ordering isn't arbitrary — it's a standing lesson from this
  project's own incident history that security groups are the most commonly *suspected* cause of a
  networking problem and, in practice, the least likely to actually be it (see the Calico
  encapsulation bug in the top-level `CLAUDE.md` for a case that looked exactly like an SG problem
  and wasn't one).
- **`/fix <area>`** — the router. Takes one word — `version`, `nat`, `sg`, `alb`, `istio`, `gitops`,
  `probes`, `images`, `comments`, or `cost` — and hands it to the one specialist who owns that area,
  while enforcing a dependency order: version/cluster-formation issues must be fixed before
  Istio/GitOps issues, which must be fixed before application/probe issues, because none of the later
  layers can be verified working until the ones beneath them actually form correctly.
- **`/plan-infra`** — a heavier planning wrapper for bigger asks: forces deeper reasoning
  ("ultrathink"), stays entirely read-only, and stops at a numbered, human-approved plan before
  anything is edited. Useful when a task is bigger than a single `/fix` call.
- **`/sg-audit`** — a narrow, single-purpose audit of just the Kubernetes security-group chain,
  cross-checking what the Terraform actually declares against live AWS state, and explicitly refusing
  to propose widening anything to `0.0.0.0/0` as a shortcut.

## The philosophy this encodes

Taken together, this directory encodes one consistent idea, repeated at every layer: **diagnosis is
read-only and cheap to re-run; a fix is always a reviewed diff, never a silent edit; and an actual
mutation against AWS or the cluster is a distinct, explicit, human-triggered action that happens
outside any agent's own initiative.** The specialization by domain mirrors how a real platform team
divides this same work across people, and the fixed remediation order (cluster formation, then
service mesh, then application) mirrors a real dependency graph this project learned the hard way —
see the bootstrap bugs recorded in the top-level `CLAUDE.md` for exactly why "check the version
alignment before you chase a mesh problem" is a rule earned from a live incident, not a preference.
