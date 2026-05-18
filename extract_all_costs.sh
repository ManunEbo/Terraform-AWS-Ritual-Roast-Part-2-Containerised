#!/bin/bash

# Base to Euston: Unified Multi-Tier FinOps Pipeline

echo "Initializing DevSecOps Cost Extraction..."

# Check if 'jq' is installed
if ! command -v jq &> /dev/null; then
    echo "⚠️ 'jq' is not installed. Initiating automated installation..."
    sudo apt-get update -qq && sudo apt-get install -y jq
    echo "✅ 'jq' successfully installed."
fi

echo "🚀 Scanning Tier-0 and Tier-1 infrastructures simultaneously..."

# Run the master config and pipe all projects into a single CSV
INFRACOST_CURRENCY=GBP infracost breakdown \
  --config-file infracost-config.yml \
  --format json | jq -r '.projects[].breakdown.resources[]? | [.name, .monthlyCost] | @csv' > unified_infracost_raw.csv

if [ $? -eq 0 ]; then
    echo "🎉 Mission Accomplished! Telemetry securely merged into 'unified_infracost_raw.csv'."
else
    echo "❌ Error: The Infracost extraction pipeline failed."
fi
