---
description: Optional richer planning wrapper — forces deep thinking (ultrathink), routes read-only investigation through the infra subagents, and stops at a numbered plan for approval. The native /plan command already enters plan mode on its own; use this when you want the full investigation recipe without retyping it.
argument-hint: <what to plan, e.g. "fix worker-to-NLB traffic in 05-aws-k8s">
---

ultrathink

Plan only. Do NOT edit files and do NOT run any command that changes infrastructure
(`terraform apply`/`destroy`, `kubectl apply`/`delete`, etc.). Read-only diagnostics are fine.
For an additional hard stop on edits, this pairs well with the native `/plan` command or Shift+Tab.

**Task:** $ARGUMENTS

Work through it carefully:

1. Read `CLAUDE.md` for context. Use the `infra-explorer` subagent (read-only) to locate every
   file relevant to the task, and the `k8s-network-debugger` subagent if this involves
   networking or security groups.
2. Reconstruct the *intended* behavior, then compare it against what the code actually does.
   Cite findings by `file : resource`.
3. Produce a numbered plan: the smallest, safest set of changes, the exact files/resources to
   touch, the reason for each, the blast radius, the AWS cost impact (suggest `infracost diff`),
   and how we will verify success.

Stop after presenting the plan and wait for my explicit approval before doing anything.
