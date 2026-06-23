---
description: Read-only audit of the Kubernetes security groups and traffic path; reports gaps and minimal fixes.
argument-hint: (optional) a specific hop, e.g. "NLB to backend workers"
---

Run a **read-only** audit of the `05-aws-k8s` networking. Do not edit anything or run any
mutating command.

Use the `k8s-network-debugger` subagent. For the path
`ALB/NLB ingress → worker nodes (NodePort / Istio ingress gateway) → Flask & Next.js pods`
(focus: $ARGUMENTS if provided):

1. For each hop, state the ports and source/destination SG or CIDR that should be allowed.
2. Compare against the rules actually defined in `infrastructure/05-aws-k8s/modules/security_k8s/` (`nlb-sg.tf`, `controlplane-sg.tf`, `worker-backend-sg.tf`, `worker-frontend-sg.tf`) and `infrastructure/05-aws-k8s/modules/network_k8s/`.
3. Cross-check against live AWS where possible using `aws ec2 describe-security-groups` and
   `aws elbv2 describe-*` (read-only).

Report a prioritized table of gaps: `file : resource`, what's wrong, the exact rule to add/fix,
and the risk. Do not propose widening anything to `0.0.0.0/0`. Do not change anything.
