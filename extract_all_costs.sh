#!/bin/bash
# =============================================================================
# Ritual Roast - per-layer FinOps extraction
# Run from the repo ROOT (the directory that holds infracost-config.yml).
#
# Outputs:
#   unified_infracost_raw.csv   Layer,Resource,MonthlyCost  (one row per resource, tagged by
#                               layer). THIS is the file the dashboard macro reads - copy it to
#                               the Windows path set in the macro's CSV_PATH constant.
#   per_layer_totals.csv        Layer,MonthlyCost per layer + a single grand Total row.
#
# ECS (04) and K8s (05) stay as their own layers, so both files break them out separately.
# =============================================================================

set -uo pipefail

CONFIG="infracost-config.yml"
JSON="infracost_breakdown.json"
RAW="unified_infracost_raw.csv"
TOTALS="per_layer_totals.csv"
CURRENCY="${INFRACOST_CURRENCY:-GBP}"

command -v jq        >/dev/null 2>&1 || { echo "jq not found; install jq" >&2; exit 1; }
command -v infracost >/dev/null 2>&1 || { echo "infracost not found; install it" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "ERROR: $CONFIG not found - run this from the repo root." >&2; exit 1; }

echo "Running infracost across all layers (${CURRENCY})..."
INFRACOST_CURRENCY="$CURRENCY" infracost breakdown --config-file "$CONFIG" --format json > "$JSON"
if [ $? -ne 0 ] || [ ! -s "$JSON" ]; then
  echo "ERROR: infracost breakdown failed (no JSON produced)." >&2
  exit 1
fi

# Dashboard feed: every resource, tagged by its layer.
{ echo '"Layer","Resource","MonthlyCost"'
  jq -r '.projects[] | .name as $p | .breakdown.resources[]? | [$p, .name, (.monthlyCost // "0")] | @csv' "$JSON"
} > "$RAW"

# Per-layer totals + a single grand Total (no phase split).
jq -r '
  (["Layer","MonthlyCost"]),
  ( .projects[] | [ .name, ((.breakdown.totalMonthlyCost) // "0") ] ),
  (["Total", ([ .projects[] | ((.breakdown.totalMonthlyCost) // "0" | tonumber) ] | add)])
  | @csv
' "$JSON" > "$TOTALS"

echo "Done:"
echo "  $RAW      (copy this to the Windows path in the macro; Layer,Resource,MonthlyCost)"
echo "  $TOTALS   (per-layer totals + grand Total)"
