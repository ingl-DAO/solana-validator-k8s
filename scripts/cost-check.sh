#!/usr/bin/env bash
# Pull actual spend from the OCI usage API and drop a dated snapshot into docs/evidence/cost/.
#
#   ./scripts/cost-check.sh          # last 7 days, daily
#   ./scripts/cost-check.sh 30       # last 30 days
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib/oci-common.sh
oci_select_profile || exit 1

DAYS="${1:-7}"
START="$(date -u -d "$DAYS days ago" +%Y-%m-%dT00:00:00Z)"
END="$(date -u -d 'tomorrow' +%Y-%m-%dT00:00:00Z)"
OUT="docs/evidence/cost"
mkdir -p "$OUT"
STAMP="$(date -u +%Y-%m-%d)"

echo "usage $START -> $END"
echo

RAW="$OUT/usage-$STAMP.json"
oci_t usage-api usage-summary request-summarized-usages \
  --tenant-id "$OCI_TENANCY" \
  --time-usage-started "$START" \
  --time-usage-ended "$END" \
  --granularity DAILY \
  --query-type COST \
  --group-by '["service"]' \
  > "$RAW" 2>/dev/null || {
    echo "usage-api call failed. It can lag ~24h on a fresh tenancy, and trial accounts"
    echo "sometimes expose nothing until the first full billing day. Check the Console:"
    echo "  Billing & Cost Management -> Cost Analysis"
    exit 1
  }

echo "=== by service ==="
jq -r '[.data.items[]? | {s: .service, c: (.computedAmount // 0), u: .currency}]
       | group_by(.s)[]
       | "\(.[0].s)\t\(map(.c) | add | .*100 | round / 100) \(.[0].u)"' "$RAW" \
  | sort -k2 -rn | { command -v column >/dev/null && column -t || cat; }

echo
echo "=== total ==="
jq -r '[.data.items[]?.computedAmount // 0] | add | . * 100 | round / 100' "$RAW" \
  | xargs -I{} echo "{} $(jq -r '.data.items[0].currency // "?"' "$RAW") over $DAYS days"

echo
echo "raw: $RAW"
echo "Modelled: Variant B ~\$29.60 for the whole build. Compare in docs/cost-report.md."
