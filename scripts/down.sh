#!/usr/bin/env bash
# Teardown with a zero-orphan assertion. The committed output of this script is what makes the
# "I cleaned up after myself" claim checkable rather than assertable.
set -euo pipefail
ENV_DIR="terraform/envs/oci-testnet"
: "${OCI_COMPARTMENT_ID:?set OCI_COMPARTMENT_ID}"

# helm first. A dangling CCM-created LoadBalancer blocks subnet deletion and hangs
# `terraform destroy` — the classic OKE teardown failure.
helm uninstall solana --wait --timeout 5m || true
echo "waiting for any LoadBalancer to disappear..."
for _ in {1..30}; do
  [[ -z "$(kubectl get svc -A -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' 2>/dev/null)" ]] && break
  sleep 10
done

terraform -chdir="$ENV_DIR" destroy -auto-approve

echo "=== orphan check ==="
fail=0
check() {
  local label="$1"; shift
  local out; out=$("$@" 2>/dev/null | jq -r '.data // [] | length')
  printf '%-24s %s\n' "$label" "${out:-0}"
  [[ "${out:-0}" == "0" ]] || fail=1
}
check "compute instances"  oci compute instance list       -c "$OCI_COMPARTMENT_ID" --lifecycle-state RUNNING
check "oke clusters"       oci ce cluster list             -c "$OCI_COMPARTMENT_ID"
check "block volumes"      oci bv volume list              -c "$OCI_COMPARTMENT_ID" --lifecycle-state AVAILABLE
check "boot volumes"       oci bv boot-volume list         -c "$OCI_COMPARTMENT_ID" --lifecycle-state AVAILABLE
check "load balancers"     oci lb load-balancer list       -c "$OCI_COMPARTMENT_ID"
check "network lbs"        oci nlb network-load-balancer list -c "$OCI_COMPARTMENT_ID"
check "vcns"               oci network vcn list            -c "$OCI_COMPARTMENT_ID"

if (( fail )); then
  echo "ORPHANS REMAIN — do not claim a clean teardown"; exit 1
fi
echo "zero orphans"
