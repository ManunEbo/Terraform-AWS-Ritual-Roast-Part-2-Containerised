#!/usr/bin/env bash
# =================================================================
# Push (create or update) ritual-roast-mesh-dashboard.json to Grafana
# Cloud via the HTTP API — no manual Dashboards -> Import click-through.
#
# This does NOT touch the cluster, ArgoCD, or Terraform. It only talks
# to Grafana Cloud's own API, using credentials you provide below. Re-run
# any time after editing the dashboard JSON; overwrite:true means it
# updates the existing dashboard (matched by "uid" in the JSON) instead
# of erroring on a duplicate.
#
# ---- Get GRAFANA_URL ----
# Grafana Cloud -> your stack -> "Launch"/"Details". It looks like
# https://<your-org>.grafana.net  (NOT the Prometheus remote-write URL
# from rr-dev-grafana-remote-write-url — that's a different host/path).
#
# ---- Get GRAFANA_API_TOKEN ----
# This must be a Grafana-instance Service Account token (Editor or Admin
# role), NOT the Alloy remote-write Access Policy token in
# rr-dev-grafana-cloud-token (that one is scoped metrics:write only and
# cannot create dashboards).
#   Grafana Cloud UI -> your stack -> Administration -> Users and access
#   -> Service accounts -> Add service account (role: Editor) -> Add
#   service account token -> copy it once, it's shown only at creation.
#
# ---- Usage ----
#   export GRAFANA_URL="https://<your-org>.grafana.net"
#   export GRAFANA_API_TOKEN="glsa_xxxxxxxx"
#   ./push-to-grafana.sh
#
# Optional overrides:
#   GRAFANA_DATASOURCE_NAME   exact name of the Prometheus datasource in
#                             this Grafana instance (default: auto-detect
#                             the first datasource of type "prometheus")
#   GRAFANA_FOLDER_UID        folder uid to save into (default: General)
# =================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_JSON="${SCRIPT_DIR}/ritual-roast-mesh-dashboard.json"

: "${GRAFANA_URL:?Set GRAFANA_URL, e.g. https://your-org.grafana.net (see header comment)}"
: "${GRAFANA_API_TOKEN:?Set GRAFANA_API_TOKEN — a Grafana Service Account token, Editor+ role (see header comment)}"
GRAFANA_URL="${GRAFANA_URL%/}"

for bin in curl jq; do
  command -v "$bin" >/dev/null || { echo "Missing required tool: $bin" >&2; exit 1; }
done
[[ -f "$DASHBOARD_JSON" ]] || { echo "Dashboard file not found: $DASHBOARD_JSON" >&2; exit 1; }

auth=(-H "Authorization: Bearer ${GRAFANA_API_TOKEN}" -H "Content-Type: application/json")

if [[ -z "${GRAFANA_DATASOURCE_NAME:-}" ]]; then
  echo "No GRAFANA_DATASOURCE_NAME set — auto-detecting a Prometheus datasource..." >&2
  ds_json=$(curl -fsS "${auth[@]}" "${GRAFANA_URL}/api/datasources")
  GRAFANA_DATASOURCE_NAME=$(echo "$ds_json" | jq -r '[.[] | select(.type=="prometheus")][0].name // empty')
  if [[ -z "$GRAFANA_DATASOURCE_NAME" ]]; then
    echo "No Prometheus datasource found at ${GRAFANA_URL}/api/datasources." >&2
    echo "List available datasources with:" >&2
    echo "  curl -H \"Authorization: Bearer \$GRAFANA_API_TOKEN\" ${GRAFANA_URL}/api/datasources | jq '.[] | {name,type}'" >&2
    echo "Then re-run with GRAFANA_DATASOURCE_NAME=<name> set explicitly." >&2
    exit 1
  fi
fi
echo "Using Prometheus datasource: ${GRAFANA_DATASOURCE_NAME}" >&2

payload=$(jq -n \
  --slurpfile dashboard "$DASHBOARD_JSON" \
  --arg ds "$GRAFANA_DATASOURCE_NAME" \
  --arg folder "${GRAFANA_FOLDER_UID:-}" \
  '{
    dashboard: $dashboard[0],
    overwrite: true,
    inputs: [
      { name: "DS_PROMETHEUS", type: "datasource", pluginId: "prometheus", value: $ds }
    ]
  } + (if $folder != "" then { folderUid: $folder } else {} end)')

echo "Pushing ${DASHBOARD_JSON##*/} to ${GRAFANA_URL} ..." >&2
resp=$(curl -fsS -X POST "${auth[@]}" "${GRAFANA_URL}/api/dashboards/import" -d "$payload")

url_path=$(echo "$resp" | jq -r '.importedUrl // .imported.url // empty')
if [[ -n "$url_path" ]]; then
  echo "Done. Dashboard URL: ${GRAFANA_URL}${url_path}"
else
  echo "Grafana response:" >&2
  echo "$resp" | jq .
fi
