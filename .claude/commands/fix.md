---
description: Route a specific fix to the right remediation engineer. The fixer proposes a diff and stops for approval — it never applies to AWS or the cluster.
argument-hint: <area> — one of version | nat | sg | alb | istio | gitops | probes | images | comments | cost
---

Read CLAUDE.md first. PROPOSE changes only — do NOT run terraform apply/destroy, kubectl apply/delete, docker push, helm upgrade, or argocd sync. Read-only validation is fine. For each change, present a unified diff (or manifest), the reason, the blast radius, the cost impact, and the verification step, then STOP for my approval.

Area requested: $ARGUMENTS

Route to the correct subagent:
- version | nat | sg | alb | ecs-healthcheck   -> use the `platform-engineer` subagent (Terraform / AWS / user_data).
- istio | gitops | argocd | probes (the K8s manifests) -> use the `k8s-gitops-engineer` subagent (Kubernetes / Istio / ArgoCD).
- images | comments | app | dockerfile | health-endpoint -> use the `app-build-engineer` subagent (app code / Dockerfiles).
- cost | infracost | finops | usage -> use the `finops-engineer` subagent (infracost usage files / config / extraction script).

Respect the dependency order if more than one area is requested: version alignment FIRST (nothing networks until Calico fits the API server), THEN istio/gitops, THEN app/probes. If the requested area depends on an unfinished prior fix, say so and propose the prerequisite first rather than a fix that can't be validated yet. The cost/finops area is independent of the version -> istio/gitops -> app order; it can run at any time.
