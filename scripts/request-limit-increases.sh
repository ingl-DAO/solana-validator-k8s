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

# --- identify the tenancy -----------------------------------------------------------------------
TENANCY="${OCI_TENANCY_OCID:-$(oci iam compartment list --access-level ACCESSIBLE \
  --compartment-id-in-subtree true --all 2>/dev/null | jq -r '.data[0]."compartment-id"' || true)}"
[[ -n "${TENANCY:-}" && "$TENANCY" != "null" ]] || {
  echo "Could not determine the tenancy OCID."
  echo "Run 'oci session authenticate' first, or export OCI_TENANCY_OCID=ocid1.tenancy.oc1..."
  exit 1
}
REGION="$(oci iam region-subscription list --tenancy-id "$TENANCY" \
  | jq -r '.data[] | select(."is-home-region"==true)."region-name"')"
echo "tenancy: $TENANCY"
echo "home region: $REGION"
echo

# --- discover the ACTUAL limit names and current values -----------------------------------------
# Do not hardcode these. Limit names differ by shape family and the console spelling is not
# always what the API uses.
echo "=== current compute limits matching e4 ==="
oci limits value list --service-name compute --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | select(.name|test("e4")) | "\(.name)\t\(."availability-domain" // "REGION")\t\(.value)"' \
  | sort | column -t
echo
echo "=== current block-storage limits ==="
oci limits value list --service-name block-storage --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | "\(.name)\t\(."availability-domain" // "REGION")\t\(.value)"' \
  | sort | column -t
echo

# Pick the AD with the E4 core limit. If several, take the first — capacity varies by AD and the
# node pool pins to one anyway (var.availability_domain).
AD="$(oci limits value list --service-name compute --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | select(.name=="standard-e4-core-count") | ."availability-domain"' | head -1)"
[[ -n "$AD" ]] || { echo "No standard-e4-core-count limit found — check the shape family name above."; exit 1; }
echo "targeting AD: $AD"

# --- build the request --------------------------------------------------------------------------
ITEMS=$(jq -n --arg r "$REGION" --arg ad "$AD" '[
  { serviceName: "compute",
    limitName:   "standard-e4-core-count",
    scope:       "AD",
    region:      $r,
    availabilityDomain: $ad,
    value:       16 },
  { serviceName: "block-storage",
    limitName:   "total-storage-gb",
    scope:       "AD",
    region:      $r,
    availabilityDomain: $ad,
    value:       1024 }
]')

JUSTIFICATION="Running a single non-voting Solana testnet node on OKE for a public \
infrastructure-as-code reference project. The 6 OCPU per-AD cap on VM.Standard.E4.Flex prevents \
using Ultra High Performance block volumes, which require multipath attachment and therefore 16 \
OCPU. The 200 GB aggregate block volume limit includes boot volumes, which with a 50 GB minimum \
volume size leaves insufficient room for the node's ledger. Single tenancy, single node, \
short-lived."

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
