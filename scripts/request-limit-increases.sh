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

CONFIG="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"
PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
[[ -f "$CONFIG" ]] || { echo "No $CONFIG. Run 'oci session authenticate' first."; exit 1; }

# Read a key out of the [PROFILE] section of the config. No API call, no auth needed.
cfg() {
  awk -v p="[$PROFILE]" -v k="$1" '
    $0==p {inp=1; next}
    /^\[/ {inp=0}
    inp && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
    }' "$CONFIG"
}

TENANCY="${OCI_TENANCY_OCID:-$(cfg tenancy)}"
REGION="${OCI_REGION:-$(cfg region)}"
TOKEN_FILE="$(cfg security_token_file)"

[[ -n "$TENANCY" ]] || { echo "No 'tenancy' in profile [$PROFILE] of $CONFIG."; exit 1; }
[[ -n "$REGION"  ]] || { echo "No 'region' in profile [$PROFILE] of $CONFIG.";  exit 1; }

# `oci session authenticate` writes a session token. Commands MUST be told to use it, otherwise
# the CLI silently attempts API-key auth and every call fails with a confusing auth error.
if [[ -n "$TOKEN_FILE" ]]; then
  export OCI_CLI_AUTH=security_token
  echo "auth: security_token (profile [$PROFILE])"
else
  echo "auth: api_key (profile [$PROFILE])"
fi
export OCI_CLI_PROFILE="$PROFILE"

echo "tenancy: $TENANCY"
echo "region:  $REGION"
echo

# Fail loudly if the session is expired rather than producing an empty limit list.
if ! oci iam region-subscription list --tenancy-id "$TENANCY" >/dev/null 2>&1; then
  echo "ERROR: the session token is not working. Refresh it with:"
  echo "  oci session refresh --profile $PROFILE"
  echo "or re-run: oci session authenticate"
  exit 1
fi

# --- discover the ACTUAL limit names and current values -----------------------------------------
# Do not hardcode these. Limit names differ by shape family and the console spelling is not
# always what the API uses.
fmt() { if command -v column >/dev/null; then column -t; else cat; fi; }

echo "=== current compute limits matching e4 ==="
oci limits value list --service-name compute --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | select(.name|test("e4")) | "\(.name)\t\(."availability-domain" // "REGION")\t\(.value)"' \
  | sort | fmt
echo
echo "=== current block-storage limits ==="
oci limits value list --service-name block-storage --compartment-id "$TENANCY" --all \
  | jq -r '.data[] | "\(.name)\t\(."availability-domain" // "REGION")\t\(.value)"' \
  | sort | fmt
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
