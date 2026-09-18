#!/usr/bin/env bash
# Session 1, step 2: file the OCI service limit increase requests.
#
# Two limits gate this project, and NEITHER is a money constraint — the trial balance is barely
# touched. They are hard service limits on a fresh tenancy:
#
#   1. standard-e4-core-count      6  -> 16   Compute OCPUs for VM.Standard.E4.Flex, per AD.
#                                             16 is not arbitrary: Ultra High Performance block
#                                             volumes require multipath attachment, which requires
#                                             >=16 OCPU. At 6 it is unreachable at any price.
#   2. block-storage total-storage 200 -> 1024 GB. The 200 GB cap INCLUDES boot volumes, and the
#                                             per-volume minimum is 50 GB, which is what forces
#                                             the single-node / single-PVC design (ADR 0007).
#
# Approval is not guaranteed and may not be available to trial accounts at all — Oracle's docs do
# not say either way. Treat this as fire-and-forget: the plan is designed to work at 6 OCPU and
# 200 GB as shipped. If it IS granted, revisit the storage tier decision.
#
# Usage:
#   oci session authenticate          # browser login, once
#   ./scripts/request-limit-increases.sh [--dry-run]
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

command -v oci >/dev/null || { echo "oci CLI not found. pipx install oci-cli"; exit 1; }
command -v jq  >/dev/null || { echo "jq not found"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/oci-common.sh
source "$SCRIPT_DIR/lib/oci-common.sh"

oci_select_profile || exit 1
TENANCY="$OCI_TENANCY"
REGION="$OCI_REGION_NAME"
echo "tenancy: $TENANCY"
echo

# --- discover the ACTUAL limit names and current values -----------------------------------------
# Do not hardcode these. Limit names differ by shape family and the console spelling is not always
# what the API uses. Two of this plan's load-bearing constraints were wrong until this was run.
fmt() { if command -v column >/dev/null; then column -t; else cat; fi; }

echo "=== compute limits you can actually use (non-zero, excluding reserved) ==="
oci_t limits value list --service-name compute --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | select(.value > 0 and .value < 1000000) | select(.name|test("core-count|memory-count")) | "\(.value)\t\(.name)\t\(."availability-domain" // "REGION")"' \
  | sort -k2 | fmt
echo
echo "=== block-storage limits ==="
oci_t limits value list --service-name block-storage --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | "\(.value)\t\(.name)\t\(."availability-domain" // "REGION")"' \
  | sort -k2 | fmt
echo

LIMIT_NAME="${LIMIT_NAME:-standard-e5-core-count}"
TARGET_OCPU="${TARGET_OCPU:-16}"

CURRENT="$(oci limits value list --service-name compute --compartment-id "$TENANCY" --all \
  | jq -r --arg n "$LIMIT_NAME" '.data[] | select(.name==$n) | .value' | head -1)"
AD="$(oci limits value list --service-name compute --compartment-id "$TENANCY" --all \
  | jq -r --arg n "$LIMIT_NAME" '.data[] | select(.name==$n) | ."availability-domain"' | head -1)"
if [[ -z "$AD" || "$AD" == "null" ]]; then
  echo "No '$LIMIT_NAME' limit found. Use an exact name from the table above,"
  echo "or override: LIMIT_NAME=standard-e3-core-ad-count $0"
  exit 1
fi
echo "targeting AD: $AD   ($LIMIT_NAME currently $CURRENT, requesting $TARGET_OCPU)"
if [[ "${CURRENT:-0}" -ge "$TARGET_OCPU" ]]; then
  echo "Already at or above $TARGET_OCPU. Nothing to request."
  exit 0
fi

# --- build the request --------------------------------------------------------------------------
# Block storage is deliberately NOT requested. Verified 2026-09-18: total-storage-gb is already
# 30720 GB per AD. The 200 GB figure that drove the original single-PVC design is
# total-free-storage-gb -- the Always Free allowance, which does not bind a credit-funded trial.
ITEMS=$(jq -n --arg r "$REGION" --arg ad "$AD" --arg n "$LIMIT_NAME" --argjson v "$TARGET_OCPU" '[
  { serviceName: "compute",
    limitName:   $n,
    scope:       "AD",
    region:      $r,
    availabilityDomain: $ad,
    value:       $v }
]')

JUSTIFICATION="Running a single non-voting Solana testnet node on OKE for a public \
infrastructure-as-code reference project. The current ${CURRENT} OCPU per-AD limit on \
VM.Standard.E5.Flex is below the 16 OCPU required for multipath block volume attachment, which \
is in turn required for the Ultra High Performance storage tier that this IO-sensitive workload \
needs. Single tenancy, single node, short-lived."

echo
echo "=== request payload ==="
echo "$ITEMS" | jq .
echo
echo "justification: $JUSTIFICATION"
echo

if (( DRY_RUN )); then
  echo "(--dry-run: nothing submitted)"
  exit 0
fi

read -rp "Submit this limit increase request to Oracle? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted"; exit 0; }

oci limits-increase limits-increase-request create \
  --compartment-id "$TENANCY" \
  --display-name "solana-validator-k8s: E4 OCPU and block storage" \
  --justification "$JUSTIFICATION" \
  --items "$ITEMS" \
  --wait-for-state ACCEPTED \
  | tee docs/evidence/oci/limit-increase-request.json

echo
echo "Filed. Track with:"
echo "  oci limits-increase limits-increase-request list -c $TENANCY"
