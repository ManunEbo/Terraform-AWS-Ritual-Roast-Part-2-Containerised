# Layer 5 — Self-Managed Kubernetes, Istio & GitOps

This is the second of the project's two deployment platforms, and by far the most involved layer in
the whole project. Where `infrastructure/04-aws-ecs` runs the applications on AWS's managed container
service, this layer builds and operates an entire **Kubernetes cluster from scratch** — the control
plane, the pod networking, the service mesh, and the continuous-deployment pipeline that keeps it in
sync with git — on plain EC2 instances, with nothing managed by AWS beyond the virtual machines
themselves. It exists to run the same applications a second way, and specifically to host a live,
observable comparison between the original app ("v1") and a rewritten challenger ("v2"), shifting
real traffic between them using every major progressive-delivery strategy: canary, blue-green, and
traffic shadowing.

If Kubernetes is unfamiliar: think of it as an operating system for a whole fleet of servers rather
than one machine. You describe the end state you want ("two copies of this container, always
running, always reachable at this address") and Kubernetes continuously works to keep reality
matching that description — restarting a crashed copy, rerouting traffic away from an unhealthy one,
without a human doing it by hand. **Istio** sits on top of that and manages traffic *between*
services — including the ability to say "send 90% of requests to version A and 10% to version B,"
which is the entire mechanism this layer uses to run its canary experiments. **ArgoCD** is what keeps
the cluster's actual state matching what's committed in this git repository, automatically, so a
deployment is a `git push`, not a manual command run against a live cluster.

## What this layer builds

| Module | Creates |
|---|---|
| `modules/compute_k8s` | Three control-plane EC2 instances (HA, embedded etcd) and two separate worker node pools — one for frontend workloads, one for backend — each bootstrapped entirely by a `user_data` script. |
| `modules/network_k8s` | This layer's own NAT gateway, scoped to just the K8s subnets. |
| `modules/load-balancers_k8s` | The rule that attaches this cluster onto the shared public ALB from layer 1. |
| `modules/security_k8s` | Five security groups covering every hop of cluster traffic (including the Calico overlay), plus three narrowly-scoped secrets. |
| `modules/iam_k8s` | Three IAM roles — control plane, frontend workers, backend workers — each scoped to only the Secrets Manager entries that node type actually needs. |
| `k8s-manifests/` | Everything ArgoCD deploys once the cluster exists: the v1 and v2 application Deployments/Services, the Istio traffic-routing rules, and the observability stack. |

## The traffic path

```
Internet
   │
   ▼
Public ALB  (layer 1's shared ALB — this layer's rule: priority 10, path "/*")
   │
   ▼
Target group :30080          (a NodePort the Istio ingress gateway listens on)
   │
   ▼
Frontend worker node → kube-proxy → istio-ingressgateway pod :80
   │
   ▼
Gateway / VirtualService  (Istio — decides v1 vs v2, by cookie or by weight)
   │
   ▼
Frontend Service → Next.js (v1) or Vite/nginx (v2) pod
   │  server-side call (v1 only) — the Istio sidecar intercepts this too
   ▼
Backend Service → Flask (v1) or Go (v2) pod
   │
   ▼
RDS MySQL (layer 2) + Secrets Manager (via the VPC endpoint from layer 1)
```

A separate, unrelated load balancer — an internal **Network Load Balancer** on port 6443 — exists
purely for the Kubernetes API server itself (node-to-node cluster communication and joining), not
for application traffic. It's easy to conflate the two; they don't share a listener, a target group,
or a purpose.

---

## 1. Compute: three control-plane nodes, two specialized worker pools

```hcl
resource "aws_autoscaling_group" "rr_k3s_cp_asg" {
  desired_capacity = 3   # HA architecture
  max_size = 3
  min_size = 3
}
```

The control plane runs as a fixed-size Auto Scaling Group of **three** `t3.medium` instances — not
one, and not an elastic range — because K3s here runs with its **embedded etcd** in HA mode, which
needs an odd number of members (3, in this case) to hold a quorum vote if one node is lost. Two
further worker Auto Scaling Groups (`t3.medium` each, desired 1 / max 4) are kept deliberately
separate — a **frontend** pool and a **backend** pool — each tainted (`dedicated=frontend:NoSchedule`
/ `dedicated=backend:NoSchedule`) and labelled (`tier: frontend` / `tier: backend`) so the frontend
and backend Deployments (via a matching `nodeSelector` + `tolerations` pair — see the manifests
below) land only on the pool built for them, rather than mixing on whichever node happens to have
room. The AMI is looked up dynamically (`data.aws_ami`, most-recent Amazon Linux 2023) rather than a
hard-coded ID, so a redeploy always starts from a current, patched base image.

## 2. Bootstrapping an HA cluster: leader election over EC2 tags

K3s's HA mode needs exactly one node to run `--cluster-init` (creating the etcd cluster) while every
other control-plane node *joins* that one — get this wrong and you get either zero clusters or a
split-brain of several. This project doesn't use an external coordination service for that decision;
`user_data_cp.sh` derives it from AWS itself:

```bash
# Gate: wait until all 3 CP instances are 'running', so every node sees the
# same IP set and deterministically agrees on the same leader.
while true; do
  CP_COUNT=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=rr-$ENVIRONMENT-k3s-control-plane" \
    "Name=instance-state-name,Values=running" --query 'length(Reservations[*].Instances[*])' --output text)
  [ "$CP_COUNT" -ge 3 ] && break
  sleep 15
done

EXISTING_CP=$(aws ec2 describe-instances --filters ... --query "...PrivateIpAddress" --output text \
  | tr '\t' '\n' | sort | head -n 1)   # lowest private IP wins, deterministically

if [ -z "$EXISTING_CP" ] || [ "$EXISTING_CP" == "$MY_IP" ]; then
  # I am the leader — initialize the cluster
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.15+k3s1" sh -s - server --cluster-init ...
else
  # Someone else is the leader — join them
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.15+k3s1" sh -s - server --server https://$EXISTING_CP:6443 ...
fi
```

Every node waits until all three control-plane instances are visibly `running` in EC2 (not just
itself), so all three agree on the exact same candidate list, then deterministically picks the
lowest private IP as leader — no coordination service needed beyond the EC2 API itself. **This is
not fully idempotent**: if the specific instance holding the lowest IP is ever terminated and
replaced by the Auto Scaling Group, the new lowest-IP node could attempt `--cluster-init` again
against a cluster that already exists. That's a known, accepted risk in this dev setup (a fresh
deploy sidesteps it entirely) rather than a hardened production pattern.

The K3s version is pinned explicitly — `INSTALL_K3S_VERSION="v1.28.15+k3s1"` — on every single
install path (leader, follower, both worker types). An unpinned install would silently pull whatever
K3s considers "latest" on every new node, which is exactly the kind of drift that caused the version
skew bug described next.

## 3. Three bootstrap bugs, fixed at the source

Getting this cluster to actually come up cleanly took three separate, non-obvious fixes — each one
is now baked directly into the script, and each is worth understanding because the failure mode
wasn't where it first appeared to be.

**Bug 1 — an invalid node label silently prevented workers from ever becoming Ready.** An earlier
version of the worker bootstrap applied `--node-label node-role.kubernetes.io/worker=true` at join
time. Kubelet 1.28 rejects any `kubernetes.io`-prefixed label at registration unless it's on an
explicit allow-list, and this one isn't — so the kubelet process exited immediately on every start
attempt. The nodes could still be seen joining the API server, but they could never transition to
`Ready`. **Fix:** the label was removed from the join command entirely; the cosmetic role label can
still be applied *after* a node joins, by hand, with `kubectl label node <name>
node-role.kubernetes.io/worker=worker` — which is safe, because it's no longer part of kubelet's own
startup path.

**Bug 2 — a 120-second timeout that was too short for a loaded, freshly-booted leader.**

```bash
kubectl apply --server-side -f https://.../tigera-operator.yaml
sleep 30   # give the API server time to register the CRDs before polling
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=300s
```

`set -e` is on at the top of this script, so *any* failed command aborts the entire bootstrap.
Installing Calico's operator registers several large Custom Resource Definitions, and on a
freshly-booted, still-busy leader node, the original 120-second wait for those CRDs to become
`Established` was observed to time out — killing the script before the actual Calico
`Installation` resource was ever applied. The operator would then run forever with nothing to
install, no pod networking would come up, and everything downstream (CoreDNS, ArgoCD, every app pod)
would simply never start — while the EC2 instances themselves looked perfectly healthy. **Fix:** a
flat 30-second pre-sleep, plus raising the wait timeout to 300 seconds.

**Bug 3 — the subtlest one: Calico's default overlay mode was incompatible with sharing a subnet.**
This is the one most worth understanding in detail, because the symptom (zero pods, ArgoCD apps stuck
`Degraded`) looked nothing like the actual cause:

```yaml
# What this script applies (fixed):
spec:
  calicoNetwork:
    ipPools:
    - encapsulation: VXLAN     # "Always" — every pod packet, no exceptions
```

Upstream Calico's default pool mode is `VXLANCrossSubnet` — encapsulate pod traffic only when it
crosses a subnet boundary, and send same-subnet pod traffic as raw, unencapsulated packets for a
small performance win. This cluster's design puts multiple K3s nodes inside the *same* `/20` subnet
(see `infrastructure/01-aws-vpc/README.md`'s subnet layout), so a meaningful share of pod-to-pod
traffic — including, critically, calls from the K3s API server to the `istiod` sidecar-injection
webhook — qualified as "same subnet" and went out **unencapsulated, carrying the pod-CIDR
(`192.168.x.x`) address directly.** Two independent AWS mechanisms then silently dropped that
traffic: the EC2 network interface's **source/destination check** (on by default, and pod IPs aren't
the interface's own address) and the security groups themselves (a source-SG rule can only match
traffic from a *known* security group member — a bare pod IP is invisible to it). The practical
effect was that the Kubernetes API server couldn't reach the sidecar-injection webhook whenever both
happened to be in the same subnet, so **every pod-create request was rejected** (the webhook's
`failurePolicy: Fail` means "if you can't reach me, refuse the request" — the safe-by-default choice,
which here surfaced the problem loudly instead of masking it) — zero application pods, and no Istio
ingress gateway either, since it also needs a pod created for it. Because only *some* CP↔worker pairs
happened to share a subnet, the failure looked intermittent rather than systemic, which is what made
it the hardest of the three to isolate.

**Fix:** force every pool to `encapsulation: VXLAN` (not `VXLANCrossSubnet`) at cluster-creation time.
`VXLAN` wraps **every** pod packet — same-subnet or not — inside a UDP/4789 datagram addressed
between the *nodes'* real ENI IPs, which the security groups already explicitly permit (see the
chapter below). The pod's own IP never touches the ENI or a security group rule at all; it only ever
exists inside the encapsulated tunnel. (VXLAN *encapsulates* the packet — it does not encrypt it —
which is fine here, because that node-to-node tunnel traffic never leaves the private VPC.) This
can't be hot-patched onto a running cluster — Calico treats
an IP pool's encapsulation mode as **immutable** once the pool is created, so the fix has to be
present in the very first `Installation` manifest applied to a fresh cluster, which is why it lives
directly in `user_data_cp.sh` rather than as a follow-up `kubectl apply`.

## 4. Networking: this layer's own NAT gateway, and only this layer's

```hcl
resource "aws_nat_gateway" "rr_k8s_nat" { subnet_id = var.public_subnet_id }
resource "aws_route" "rr_inject_k8s_internet_access" {
  route_table_id = data.aws_route_table.k8s_rt.id   # layer 1's K8s route table
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.rr_k8s_nat.id
}
```

As explained in `infrastructure/01-aws-vpc/README.md`, layers 1 through 4 never provision a NAT
gateway at all — every AWS service they need has a private VPC endpoint instead. This layer is the
one exception, and for a specific reason: K3s nodes need `dnf update`, the Helm install script, and,
critically, need to pull application images from **`ghcr.io`** — GitHub Container Registry, an
external service with no AWS PrivateLink equivalent. That's genuine, unavoidable internet egress, so
this layer builds exactly one NAT gateway and injects the missing route directly into layer 1's
already-existing (but previously unrouted) K8s route table — paying for NAT exactly once, scoped to
exactly the subnets that need it.

## 5. Reaching the cluster: the ALB rule, and the separate API load balancer

```hcl
resource "aws_lb_target_group" "rr_k8s_frontend_tg" {
  port = 30080; target_type = "instance"
  health_check { path = "/"; matcher = "200" }
}
resource "aws_lb_listener_rule" "rr_k8s_absolute_cutover" {
  listener_arn = var.gateway_listener_arn   # layer 1's shared listener
  priority = 10
  condition { path_pattern { values = ["/*"] } }
}
```

This layer attaches its own rule onto the exact same shared public ALB listener that
`infrastructure/04-aws-ecs` used — at **priority 10**, a lower (higher-precedence) number than ECS's
priority 100. The two never actually contend for traffic in practice (this project destroys ECS
before deploying this layer), but the numbering means that if both were ever present simultaneously,
Kubernetes would win — the source calls this out directly as "100% cutover interception." Target type
is `instance`, not `ip`, pointed at NodePort `30080` on the **frontend** worker ASG only — that
specific ASG is what's attached to this target group, so only frontend-tainted nodes (the ones
running the Istio ingress gateway) ever receive ALB traffic.

The **API NLB** (`modules/compute_k8s/controlplane.tf`) is an entirely separate load balancer, purely
internal, forwarding TCP port 6443 to the control-plane ASG — this is what `K3S_URL` in the worker
`user_data` scripts points at, and what every `kubectl` command from a control-plane node ultimately
talks to. It has nothing to do with application traffic and shares no resources with the ALB path
above.

## 6. Security groups: five, chained, and one rule the Calico fix depends on

Every hop is a security-group-to-security-group reference, the same pattern used throughout this
project. Two details are specific to running a real Kubernetes cluster rather than a set of
independent containers:

- **UDP/4789 (VXLAN) is explicitly permitted between every node pair** — control plane ↔ frontend
  workers, control plane ↔ backend workers, and frontend ↔ backend workers directly. This is the
  rule Bug 3 above depends on existing: once Calico wraps every pod packet in a VXLAN tunnel between
  real node IPs, that tunnel traffic still has to be allowed through the security groups, or the fix
  itself would be blocked at the network layer instead of the encapsulation layer.
- **Port 6443 (the K3s API) is scoped to exactly the NLB and the worker security groups** — not
  opened broadly — and 179/TCP (Calico BGP) and 5473/TCP (Calico Typha) are similarly scoped between
  only the node types that actually need them.

## 7. Secrets: three entries, each scoped to only the nodes that need it

Three Secrets Manager entries exist purely to get the cluster bootstrapped, each created with
`recovery_window_in_days = 0` (immediate deletion on destroy — appropriate for values that are
regenerated on every fresh deploy, not long-lived credentials):

| Secret | Holds | Read by |
|---|---|---|
| `rr-{env}-k3s-join-token` | An auto-generated random token | All three node types (control plane + both worker pools) — it's the shared password that lets a new node join the cluster. |
| `rr-{env}-argocd-github-token` | A GitHub PAT | Control plane only — used once, to let ArgoCD authenticate against this private repository. |
| `rr-{env}-grafana-cloud-token` / `-remote-write-url` / `-instance-id` | Grafana Cloud credentials | Control plane only — handed to the observability namespace for the metrics-shipping Alloy agent. |

The IAM policy for each node type is scoped to only the secrets that type actually reads — frontend
workers, for instance, can read the join token and nothing else; they have no reason to ever see a
GitHub token or a Grafana credential.

## 8. GitOps: one root Application, fanning out by sync wave

The very last thing the control-plane leader's `user_data` does is apply a single ArgoCD
`Application` (`root-observability`), pointed at `k8s-manifests/observability/` in this repository.
Every other application ArgoCD manages is defined as YAML *inside* that folder — an "app of apps"
pattern, where one Terraform-created bootstrap Application is all that's ever created imperatively,
and everything else is declared in git from that point forward:

```
Wave -1 : istio-base              (Istio CRDs)
Wave  0 : Alloy ConfigMap + RBAC  (metrics shipping)
Wave  1 : istiod          | prometheus   (in-cluster, feeds Kiali's live graph)
Wave  2 : istio-ingressgateway | kiali
Wave  3 : ritual-roast-workloads (v1 apps, dev-apps/) | ritual-roast-canary (v2 apps, canary-staging/)
Wave  4 : grafana-alloy DaemonSet
```

Sync waves make the dependency order explicit: Istio's CRDs must exist before `istiod` can start,
`istiod` must be running before the ingress gateway (which needs sidecar injection) can be created,
and neither application workload wave starts until the mesh underneath it is actually functional.
Every Application in this chain runs with `syncPolicy.automated.selfHeal: true` — if anyone or
anything drifts the live cluster away from what's committed in git, ArgoCD reverts it automatically.
That's a deliberate, strict interpretation of GitOps (git is *always* the source of truth, not just
usually), and it has a real, sharp edge: because `root-observability` is itself the parent of every
other Application, a live `kubectl patch` to any child Application's own `syncPolicy` — attempting to
temporarily pause self-heal for a manual test — gets silently reverted by the *parent's* self-heal
within about a second, unless the parent's automation is paused too. Any manual, non-GitOps change
to this cluster has to account for the entire ancestor chain, not just the one Application that
appears to own the resource being changed.

## 9. Istio routing: cookies before weights, and an ordering trap worth knowing about

`k8s-manifests/dev-apps/routing/istio-routing.yml` defines one `Gateway`, two `DestinationRule`s (one
per tier, splitting pods into `v1`/`v2` subsets by their `version` pod label), and two
`VirtualService`s — and the **order of rules inside the frontend VirtualService is not cosmetic**:

```yaml
http:
- match: [{ uri: { prefix: /kiali } }]              # (0) MUST be first
  route: [{ destination: { host: kiali...svc, port: { number: 20001 } } }]
- match: [{ headers: { cookie: { regex: ".*x-frontend=v1.*" } } }]   # (1) sticky v1
  route: [{ destination: { host: rr-frontend-svc, subset: v1 } }]
- match: [{ headers: { cookie: { regex: ".*x-frontend=v2.*" } } }]   # (2) sticky v2
  route: [{ destination: { host: rr-frontend-svc, subset: v2 } }]
- route:                                             # (3) new session -> weighted split
  - { destination: { host: rr-frontend-svc, subset: v1 }, weight: 10 }
  - { destination: { host: rr-frontend-svc, subset: v2 }, weight: 90 }
```

Istio evaluates a `VirtualService`'s `http` rules top-down and stops at the first match. The `/kiali`
rule has to be **first**, ahead of both cookie rules, because a browser that has already loaded the
app carries an `x-frontend` cookie on *every* request to the same host — including a request for
`/kiali`. If the cookie rules were checked first, they'd capture that request and route it into the
frontend app instead of the Kiali dashboard, producing a 404 (v1) or the wrong single-page app (v2)
for a URL that has nothing to do with either. Below that, the two cookie rules exist so that an
established session always returns to the same version it started on — a session that landed on v1
keeps loading v1's `/_next/static/*` assets rather than being re-rolled against the canary weight on
every subsequent request, which would otherwise intermittently serve a page built from the wrong
version's JavaScript. Only a genuinely new, cookie-less session ever reaches rule (3), the actual
weighted split. The backend `VirtualService` skips the cookie step entirely — it's a stateless JSON
API with no session to keep coherent, so a pure per-request weighted split is safe.

## 10. The v1/v2 probe contract, as it actually appears in the manifests

This is the most safety-critical detail in this whole layer, covered in depth in
`apps/v2-backend-go/README.md` — here is what it looks like as delivered:

```yaml
# v1-backend-flask-deployment.yml — ONE endpoint serves every probe (shallow by construction)
livenessProbe:  { httpGet: { path: /health, port: 5000 }, periodSeconds: 20 }
readinessProbe: { httpGet: { path: /health, port: 5000 }, periodSeconds: 10 }
startupProbe:   { httpGet: { path: /health, port: 5000 }, failureThreshold: 30 }  # 150s cold-start grace

# v2-backend-go-deployment.yml — split, because /health here is DEEP (db.Ping())
livenessProbe:  { httpGet: { path: /livez,  port: 5000 }, periodSeconds: 20 }   # never touches the DB
readinessProbe: { httpGet: { path: /health, port: 5000 }, periodSeconds: 10 }   # DB-aware, readiness only
```

v1's `/health` never touches the database, so reusing one endpoint for liveness, readiness, *and* a
30-attempt startup probe (giving it roughly 150 seconds of cold-start grace before liveness can even
fail it once — directly mirroring `infrastructure/04-aws-ecs`'s 120-second ECS grace period for the
same underlying reason) is safe. v2's `/health` genuinely calls the database, which is exactly why it
is wired to **readiness only** — during an RDS Multi-AZ failover (routine, and covered in
`infrastructure/02-aws-rds/README.md`), `/health` correctly starts failing and the pod is pulled from
the Service's endpoint list, while `/livez` stays green and kubelet never restarts it. Wiring a deep
check to liveness would instead restart every backend pod at once, on every failover, compounding a
60–120 second database blip into a self-inflicted outage of the whole fleet — the failure mode this
project's internal shorthand calls "container assassination." **The rule this project follows for
every v2 manifest: never copy v1's single-endpoint probe block onto a v2 deployment.**

All four application Deployments also cap their Istio sidecar to `128Mi` memory via pod annotations
(`sidecar.istio.io/proxyMemoryLimit: "128Mi"`, down from Envoy's 1024Mi default). The cap matters
because every one of the eight app pods (four Deployments × two replicas) carries its own sidecar:
uncapped at 1024Mi, just the four sidecars that land on a single `t3.medium` worker would claim its
entire 4 GiB of RAM before the application containers got a fair share.

## 11. Canary, blue-green, and shadow — three strategies, one mechanism

Every strategy in this project is the *same* Istio primitive — the weighted route in step 9 above —
used differently:

| Strategy | How it's expressed |
|---|---|
| **Canary** | Both weights nonzero and gradually shifted (`90/10` → `50/50` → `10/90` → …), committed to `istio-routing.yml` and pushed — ArgoCD applies the new split within its poll interval. No pod is ever restarted; only the *proportion* of new sessions routed to each subset changes. |
| **Blue-green** | The same weighted route, taken all the way to `0/100` — every *new* session moves to v2 in one step, rather than gradually. |
| **Shadow (mirroring)** | An Istio `mirror:` field added to the **backend** `VirtualService` (templated in `k8s-manifests/canary-variants/vs-backend-shadow.yml`) that duplicates real, live GET requests to the v2 backend without ever returning its response to the user or affecting the official weight. It exists purely so v2 can be exercised under real production traffic before it ever serves a single real user. **It is GET-only by design** — mirroring a `POST` would insert every recipe submission into the shared database twice, once from the real request and once from the silently-mirrored copy. |

The step-by-step weight variants live in `k8s-manifests/canary-variants/` as **reference templates**,
not as files ArgoCD syncs directly — they're deliberately kept out of `dev-apps/` because a second
file defining a `VirtualService` with the same name would collide under ArgoCD's recursive folder
sync. The actual mechanism for changing traffic is always the same: edit the weight values inside
`istio-routing.yml` itself, commit, and push — this project treats "commit routing changes to a
Kubernetes-native traffic-management API" as the whole deployment mechanism, with a `git revert`
being the rollback plan for any step, canary or otherwise.

## 12. Observability: two layers of metrics, for two different jobs

| Component | Purpose | Retention |
|---|---|---|
| **Grafana Alloy** (DaemonSet, all nodes) | Scrapes Envoy sidecar metrics, remote-writes to Grafana Cloud | Long-term (external) |
| **In-cluster Prometheus** | Feeds Kiali's *live* mesh graph only | Hours, no persistent volume |
| **Kiali** | Visual mesh graph — which service is talking to which, at what volume, with traffic animation | Live only |
| **Grafana Cloud** | Long-term dashboards — request rate, error rate, p95 latency, and traffic *share* (%), all split by `destination_version` | Long-term (external) |

The Grafana Cloud dashboard (`k8s-manifests/observability/dashboards/`) is deliberately built to be
**strategy-agnostic** — every panel groups by the Istio `destination_version` label rather than by
"which canary step are we on," so the exact same dashboard reads correctly whether traffic is being
shifted via canary, blue-green, or mirrored via shadow mode (v2 shows inbound request volume on the
traffic-share panel even while its official weight is 0%, which is exactly what confirms a shadow
mirror is working). Colors are fixed across every panel — v1 green, v2 red — so a screenshot is
legible without a legend. Alloy's scrape config is deliberately trimmed to the `istio_*` metric family
only (no node or cAdvisor metrics), a direct fix for an early Grafana Cloud rate-limit (429) problem —
observability itself is cost- and quota-managed, not just the application infrastructure.

## Where this fits in the bigger picture

This layer is where the project's central experiment actually happens: `apps/v1-frontend-nextjs` +
`apps/v1-backend-flask` (the baseline) and `apps/v2-frontend-vite` + `apps/v2-backend-go` (the
challenger) run here **simultaneously**, side by side, with real traffic shiftable between them at
will — something `infrastructure/04-aws-ecs` was never built to do (ECS ran only one version of each
app, with no in-mesh traffic-splitting primitive available). Per this project's deploy sequence
(VPC → RDS → ECR → ECS → **destroy ECR and ECS** → Kubernetes), this layer takes over the exact same
shared public ALB the moment layer 4 is gone, and is the only layer where the v2 applications run at
all.
