# prompt.md — Kickoff prompt for the Kubernetes networking fix

> This is a **prompt template**, not an auto-loaded file. Paste it into Claude Code to start
> the networking work. Unlike `CLAUDE.md`, Claude does not read this automatically.
>
> Quick alternatives: the **native `/plan fix the K8s traffic flow`** enters plan mode directly,
> and the custom **`/plan-infra`** command runs this same investigation recipe (ultrathink +
> subagents + stop-for-approval) without you pasting it.

---

ultrathink

You are my infrastructure debugging partner for the Ritual Roast AWS/Terraform/Kubernetes repo.
Read `CLAUDE.md` first for context.

**Objective:** figure out why traffic is not flowing through the `05-aws-k8s` data plane and
fix it with the smallest, safest change set, in **dev only**, while keeping AWS cost down.

**Hard rules:**
- Investigate **read-only** first. Do **not** edit files yet.
- Do **not** run `terraform plan`, `terraform apply`, `terraform destroy`, or `kubectl apply`
  without my explicit approval. Never use `-auto-approve`.
- Do not widen any security group to `0.0.0.0/0` as a shortcut.

**Step 1 — Map it (read-only).**
Use the `infra-explorer` subagent to list every file involved in the traffic path and the
`k8s-network-debugger` subagent to reconstruct the *intended* path:
`ALB/NLB ingress → worker nodes (NodePort / Istio ingress gateway) → Flask & Next.js pods`.
For each hop, state the ports and the source/destination security group (or CIDR) that *should*
be allowed, then compare against what the `.tf` files actually define in
`05-aws-k8s/modules/security_k8s/` and `network_k8s/`.

**Step 2 — Diagnose.**
Identify the specific gaps: missing ingress/egress rules, wrong SG references or CIDRs,
health-check ports the load balancer can't reach, NodePort range not opened, NAT/routing issues,
or Istio ingress-gateway ports. Cite each finding by `file : resource`.

**Step 3 — Plan (stop here for approval).**
Produce a numbered plan: the minimal changes, the exact files/resources to edit, why each is
needed, the blast radius, the AWS cost impact (suggest `infracost diff`), and how we will verify
success. Then **wait** for my approval before changing anything.

**Step 4 — Execute (only after I approve).**
Make the approved edits, run `terraform plan` (I will approve the prompt), let me review the
plan, apply only after I approve, then verify with `kubectl get/describe`,
`aws ec2 describe-security-groups`, and `istioctl analyze`, and report what changed and its cost.
