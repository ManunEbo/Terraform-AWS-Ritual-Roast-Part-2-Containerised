---
description: Live POST-DEPLOYMENT check — read-only bisection of why traffic isn't flowing in a RUNNING 05-aws-k8s cluster. Requires a live cluster (run AFTER tf apply). For pre-deployment file analysis, use /audit instead.
argument-hint: (optional) a specific symptom or hop to focus on
---

ultrathink

POST-DEPLOYMENT ONLY. This command observes a LIVE cluster — it runs kubectl / aws / istioctl.
Before anything else, confirm Layer 5 is actually deployed and a cluster is reachable (e.g. a quick
`kubectl get nodes`). If it is NOT deployed yet (no tf apply), STOP immediately and tell me to run
`/audit` instead — there is nothing to observe and every live call will fail, which means nothing.

Once a live cluster is confirmed: diagnose read-only. Do NOT edit files or run any mutating command.
Read CLAUDE.md first.

Focus: $ARGUMENTS (if empty, diagnose the full path — north-south and east-west).

1. Use the `infra-explorer` subagent to map the files relevant to the symptom across the five layers
   and apps/.
2. Use the `k8s-network-debugger` subagent to run the bisection IN ORDER:
   - two probes first (curl node:30080, then kubectl get pods -A),
   - then version skew (kubectl version vs Calico 3.26.1 / Istio 1.30.1),
   - then image pulls / NAT routes,
   - then service endpoints,
   - then the mesh (proxy-status, the injection label, 2/2 vs 1/1),
   - then ALB target health (503 vs the listener's default 404),
   - and security groups LAST (they were largely cleared).

Prove each hop with a positive observation, not an inference. Report the FIRST broken hop cited by
file:resource or manifest:field, the evidence, and a prioritized fix list. Then STOP — propose
nothing destructive, and wait for me to choose what to fix with /fix.
