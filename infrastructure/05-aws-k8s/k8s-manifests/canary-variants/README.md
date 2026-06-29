# Canary / Blue-Green / Shadow variants

These VirtualService files are applied **by hand** during a live session.
They are deliberately **outside** any ArgoCD-synced path.

## Why this folder is not synced

`ritual-roast-workloads` syncs `../dev-apps/` recursively. Every canary
file here redefines a VirtualService that already exists in
`../dev-apps/routing/istio-routing.yml` (same `metadata.name`). Two
same-named objects under one sync = conflict. So this folder must never
be added to any ArgoCD Application `path:`.

## The self-heal problem (read before you start)

`ritual-roast-workloads` runs with `selfHeal: true` and `prune: true`.
With self-heal ON, ArgoCD reverts any manual `kubectl apply` back to the
Git state within ~3 minutes — it would undo your canary mid-exercise.

So for a hands-on session, turn self-heal OFF first, step through the
files, then turn it back ON.

```bash
# 1. SELF-HEAL OFF (before the session)
kubectl -n argocd patch application ritual-roast-workloads --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false,"prune":true}}}}'

# 2. Step through variants manually (examples)
kubectl apply -f vs-backend-canary-10.yml
#   ...observe in Kiali / Grafana...
kubectl apply -f vs-backend-canary-30.yml
#   ...etc...

# 3. SELF-HEAL ON (after the session) - reverts live state to Git
kubectl -n argocd patch application ritual-roast-workloads --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}'
```

With self-heal OFF but auto-sync ON, manual applies persist (shown as
OutOfSync, harmless) because Git is not changing. Auto-sync only fires
on Git changes, not on live drift.

> Alternative (pure GitOps): leave self-heal ON and instead edit the
> weights in `../dev-apps/routing/istio-routing.yml`, commit, and let
> ArgoCD sync each step (~3 min/step). More realistic, slower to iterate.

## Validate offline before the session (no cluster needed)

```bash
istioctl analyze vs-backend-canary-50.yml
kubectl apply --dry-run=client -f vs-backend-canary-50.yml
```

## Files

### Backend (stateless - pure weighted split)
| File | Effect |
|---|---|
| `vs-backend-canary-{10,30,50,70,90,100}.yml` | gradual ramp v1->v2 |
| `vs-backend-bluegreen-v2.yml` | instant 100% cutover to v2 |
| `vs-backend-shadow.yml` | mirror **GET reads only** to v2 (writes never mirrored) |

Backend rollback at any point: `kubectl apply -f ../dev-apps/routing/istio-routing.yml`

### Frontend (cookie-sticky sessions)
| File | Effect |
|---|---|
| `vs-frontend-canary-{10,30,50,70,90,100}.yml` | gradual ramp; established sessions pinned by cookie |
| `vs-frontend-bluegreen-v2.yml` | total cutover to v2 (ignores cookie) |
| `vs-frontend-bluegreen-v1.yml` | total rollback to v1 (ignores cookie) |
| `vs-frontend-shadow.yml` | low value, included for syntax only |

Frontend canary rollback: `kubectl apply -f ../dev-apps/routing/istio-routing.yml`
Frontend blue/green rollback: `kubectl apply -f vs-frontend-bluegreen-v1.yml` first
(see that file's header for why the steady-state file alone won't roll back a flip).

## Suggested learning sequence

1. Backend canary 10 -> 30 -> 50 -> 70 -> 90 -> 100 (watch the split move in Kiali)
2. Roll back; backend blue/green (feel the instant flip vs the ramp)
3. Backend shadow (watch v2 take read load with zero user impact)
4. Frontend blue/green v2, then rollback v1 (cookie-ignoring cutover)
5. Frontend canary 10 -> 50 -> 100 (watch cookie stickiness hold sessions)

Drive a little traffic each step with `hey` or `k6` (a few hundred
requests is plenty to populate metrics). Read endpoints only unless you
are explicitly testing writes.

## Dual-tier note

Backend and frontend splits are independent, so during a dual canary all
four combinations occur at once: Next.js->Flask, Vite->Go, and the two
cross-paths Next.js->Go and Vite->Flask. These are wire-compatible
(verified: GET emits `recipe_details` on both backends; POST sends
`description_main` from both frontends), so cross-paths are safe.
