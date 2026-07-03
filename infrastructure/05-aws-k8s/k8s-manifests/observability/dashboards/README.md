# Grafana Cloud dashboards

Grafana here is **Grafana Cloud** (external, remote-write target) — there is no
in-cluster Grafana and no dashboard-provisioning path via ArgoCD. These files
are dashboard-as-code kept in-repo for review/versioning; getting them into
Grafana Cloud itself is a one-time push against Grafana's own API (script
below), not a `kubectl`/ArgoCD action.

`ritual-roast-mesh-dashboard.json` is **strategy-agnostic** — it plots by
`destination_version` (v1/v2), so the same panels render whichever of canary,
blue-green, or shadow you're currently running; nothing in it assumes a
particular step.

## Push it to Grafana Cloud (recommended — one command)

```bash
export GRAFANA_URL="https://<your-org>.grafana.net"        # the stack URL, not the remote-write URL
export GRAFANA_API_TOKEN="glsa_xxxxxxxx"                    # Service Account token, Editor+ role — see below
./push-to-grafana.sh
```

`push-to-grafana.sh` POSTs the dashboard to Grafana's `/api/dashboards/import`
endpoint (the same mechanism the "Import" screen in the UI uses), auto-detects
your Prometheus datasource, and prints the dashboard URL. Re-run it any time
after editing the JSON — `overwrite:true` updates the existing dashboard
(matched by `uid`) instead of erroring on a duplicate.

**Getting `GRAFANA_API_TOKEN`** — this must be a *Grafana instance* Service
Account token, **not** the Alloy remote-write token in AWS Secrets Manager
(`rr-dev-grafana-cloud-token`) — that one is a Cloud Access Policy token scoped
`metrics:write` only and cannot create dashboards. Instead:
Grafana Cloud UI -> your stack -> **Administration -> Users and access ->
Service accounts -> Add service account** (role: Editor) -> **Add service
account token** -> copy it (shown once).

**Getting `GRAFANA_URL`** — Grafana Cloud -> your stack -> **Launch**/
**Details**. Looks like `https://<your-org>.grafana.net`. This is a different
host from the `https://prometheus-prod-XX....grafana.net/api/prom/push`
remote-write URL Alloy uses — that one is metrics ingest only, not the app.

### Manual import (alternative, no token needed)

1. Grafana Cloud -> **Dashboards -> New -> Import**.
2. Upload `ritual-roast-mesh-dashboard.json` (or paste its contents).
3. When prompted for the **Prometheus** data source input, pick your Grafana
   Cloud managed Prometheus instance (the same one `GRAFANA_REMOTE_WRITE_URL`
   points Alloy at — see `../telemetry.yml`).
4. Save. Default range is last 6h, auto-refresh 30s (matches the Alloy scrape
   interval).

## Finding the metrics yourself without a dashboard

If you just want to poke at what's already arriving, in Grafana Cloud go to
**Explore** (left nav), pick your Prometheus datasource, and use the metric
browser to type `istio_requests_total` (or `istio_request_duration_milliseconds`,
`istio_tcp_sent_bytes_total`, `up`) — those are the only series Alloy forwards
(see limit below). "Run query" with no filters first to confirm data is
flowing at all before narrowing with label filters like
`destination_version="v2"`.

## What it covers — and its limit

Built strictly from what `telemetry.yml`'s `istio_only` relabel rule actually
keeps: the `istio_*` family (+ `up`) from two scrape jobs (`sidecar_pods` in
`dev`, `gateway_pods` in `istio-ingress`). It will NOT show node/cAdvisor
metrics, non-Istio app metrics, or anything from job 3/4 — those were trimmed
2026-07-02 to stay under the Grafana Cloud ingestion rate limit. Re-add scrape
jobs there first if you want panels beyond mesh traffic.

## Panels

| Row | Panel | Query basis |
|---|---|---|
| Traffic split (canary / blue-green / shadow) | Frontend / backend request rate by version | `sum(rate(istio_requests_total{...}[5m])) by (destination_version)` |
| | Frontend / backend traffic share % | same, normalized to 100% — the live check against whatever weight is set in `../../dev-apps/routing/istio-routing.yml`; also where mirrored shadow traffic shows up on v2 even at 0% official weight |
| Reliability | Error rate % by version (lines) | 5xx / total, per version |
| | v1/v2 error rate stat tiles | thresholds: green <1%, yellow 1-5%, red >5% |
| Latency (p95) | Frontend / backend p95 by version | `histogram_quantile(0.95, ...istio_request_duration_milliseconds_bucket...)` |
| Mesh & infra health | Scrape target health | `up{namespace=~"dev\|istio-ingress"}` |
| | Backend -> RDS TCP bytes | `istio_tcp_{sent,received}_bytes_total` on the `PassthroughCluster` — this is the blue backend->PassthroughCluster edge in Kiali, expected traffic leaving the mesh, not an error |

All panels use `reporter="destination"` so each request is counted once, at the
receiving sidecar — avoids double-counting from also scraping the caller side.
**v1 is always green (`#0ca30c`), v2 always red (`#d03b3b`)**, fixed across
every panel so the same color always means the same version.

## A version with no line

If a version's error-rate or latency line is simply absent, that means
Prometheus has no matching series for that window (e.g. zero errors) — not a
scrape gap. Cross-check against the request-rate panel to confirm traffic is
actually flowing to that version.

## Driving traffic to populate it

See the "Driving/observing traffic" section in the root `CLAUDE.md` session
handover — cookieless `curl` against `/` exercises the frontend split; pin
`Cookie: x-frontend=v2` before hitting `/api/get_recipe` (v1 has no such route
and will 404 if hit cookieless).
