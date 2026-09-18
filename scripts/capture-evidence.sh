#!/usr/bin/env bash
# Capture everything needed for this repo to stay credible after the infrastructure is destroyed.
#
# The OCI trial expires and takes the cluster with it. Everything of lasting value has to be in
# git before that happens. Run this BEFORE scripts/down.sh, and not on the last day — at day 30
# you lose the ability to CREATE paid resources, and existing ones survive only a few days.
#
#   ./scripts/capture-evidence.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib/oci-common.sh

E="docs/evidence"
RELEASE="${RELEASE:-solana}"
STS="sts/${RELEASE}-solana-node"
NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)"
mkdir -p "$E"/{terraform,kubectl,network,grafana,oci,cost,teardown}

say() { printf '\n== %s\n' "$1"; }
grab() { # grab <outfile> <cmd...>
  local out="$1"; shift
  if "$@" > "$out" 2>&1; then echo "  ok   $out"; else echo "  FAIL $out ($*)"; fi
}

# ---------------------------------------------------------------- terraform
say "terraform"
( set -a; source terraform/.s3-credentials 2>/dev/null; set +a
  cd terraform/envs/oci-testnet
  # A re-run plan showing "No changes" is what a reviewer looks for: it proves the committed code
  # actually produced the running infrastructure, rather than being edited afterwards.
  terraform plan -no-color -input=false > "../../../$E/terraform/plan-no-changes.txt" 2>&1 || true
  terraform state list > "../../../$E/terraform/state-list.txt" 2>&1 || true
  terraform version > "../../../$E/terraform/version.txt" 2>&1 || true
  command -v dot >/dev/null && terraform graph | dot -Tsvg > "../../../$E/terraform/graph.svg" 2>/dev/null || true
)
grep -qE 'No changes' "$E/terraform/plan-no-changes.txt" 2>/dev/null \
  && echo "  ok   plan reports No changes" \
  || echo "  WARN plan is NOT clean — fix drift before capturing, or the evidence undercuts itself"

# ---------------------------------------------------------------- cluster
say "cluster"
grab "$E/kubectl/nodes.txt"        kubectl get nodes -o wide
grab "$E/kubectl/pods.txt"         kubectl get pods -A -o wide
grab "$E/kubectl/storage.txt"      kubectl get sc,pv,pvc -A
grab "$E/kubectl/version.txt"      kubectl version
grab "$E/kubectl/monitoring.txt"   kubectl get servicemonitor,prometheusrule -A
[[ -n "$NODE" ]] && grab "$E/kubectl/describe-node.txt" kubectl describe node "$NODE"
grab "$E/kubectl/statefulset.yaml" kubectl get "$STS" -o yaml
grab "$E/kubectl/events.txt"       kubectl get events -A --sort-by=.lastTimestamp

# ---------------------------------------------------------------- the UDP proof
# Nobody else's Solana-on-k8s repo has this, because nobody else had to fight it.
say "network (the part that is actually rare)"
if [[ -n "$NODE_IP" ]]; then
  grab "$E/network/iptables-INPUT.txt" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
       "opc@$NODE_IP" "sudo iptables -L INPUT -n -v --line-numbers"
  grab "$E/network/sysctl.txt" ssh -o ConnectTimeout=10 "opc@$NODE_IP" \
       "sysctl net.core.rmem_max net.core.wmem_max vm.max_map_count fs.nr_open"
  grab "$E/network/containerd-limits.txt" ssh -o ConnectTimeout=10 "opc@$NODE_IP" \
       'cat /proc/$(pgrep -o containerd)/limits'
  echo "  .. tcpdump (50 packets, needs live gossip)"
  ssh -o ConnectTimeout=10 "opc@$NODE_IP" \
      "sudo timeout 60 tcpdump -ni any 'udp portrange 8000-8026' -c 50 -w -" \
      > "$E/network/gossip.pcap" 2>/dev/null && echo "  ok   $E/network/gossip.pcap" || echo "  FAIL pcap"
  ssh -o ConnectTimeout=10 "opc@$NODE_IP" \
      "sudo timeout 60 tcpdump -ni any 'udp portrange 8000-8026' -c 50" \
      > "$E/network/gossip.txt" 2>&1 || true
else
  echo "  SKIP no node ExternalIP — is the pool scaled to 0?"
fi

# in-pod rlimits: proves the tuning reached the process, not just the host
grab "$E/network/pod-rlimits.txt" kubectl exec "$STS" -c validator -- \
     bash -c 'echo "nofile=$(ulimit -n) memlock=$(ulimit -l)"; cat /proc/1/limits'

# ---------------------------------------------------------------- solana
say "solana"
grab "$E/kubectl/catchup.txt" kubectl exec "$STS" -c validator -- \
     solana catchup --our-localhost 8899
grab "$E/kubectl/contact-info.txt" kubectl exec "$STS" -c validator -- \
     agave-validator --ledger /data/ledger contact-info
grab "$E/kubectl/disk-usage.txt" kubectl exec "$STS" -c validator -- \
     bash -c 'du -sh /data/ledger /data/snapshots /accounts 2>/dev/null'
grab "$E/kubectl/validator-log-tail.txt" kubectl logs "$STS" -c validator --tail=400

# the network saw us — run from OUTSIDE the cluster, which is the point
if command -v solana >/dev/null; then
  ID="$(kubectl get secret "${RELEASE}-solana-node-identity" -o jsonpath='{.data.identity\.json}' 2>/dev/null | base64 -d > /tmp/id.json && solana-keygen pubkey /tmp/id.json 2>/dev/null || true)"
  if [[ -n "${ID:-}" ]]; then
    echo "  identity: $ID"
    solana gossip --url https://api.testnet.solana.com 2>/dev/null | grep -- "$ID" \
      > "$E/network/seen-in-gossip.txt" && echo "  ok   seen in cluster gossip" \
      || echo "  WARN not visible in cluster gossip"
  fi
  rm -f /tmp/id.json
fi

# ---------------------------------------------------------------- monitoring
say "monitoring"
# The dashboard JSON is the reproducible artifact. A PNG is not — commit both, but the JSON is
# what lets someone rebuild the view.
cp charts/solana-node/dashboards/solana-node.json "$E/grafana/" 2>/dev/null && echo "  ok   dashboard json" || true
grab "$E/grafana/alert-rules.yaml" kubectl get prometheusrule -A -o yaml
cat > "$E/grafana/MANUAL.md" <<'MD'
# Screenshots to take by hand

Port-forward Grafana, then capture at 1920×1080, dark theme:

- [ ] Overview dashboard, time picker set to **≥24h**. A flat 15-minute window reads as fake.
- [ ] Template variables set to real values, not "All".
- [ ] One visible **red-then-green** incident you can explain — the deliberate pod kill is ideal.
- [ ] One alert that **fired and resolved**, with timestamps.
- [ ] The slot-lag panel during catch-up, showing the curve closing.

Save as `docs/evidence/grafana/*.png` and reference them from the README.
MD
echo "  ok   $E/grafana/MANUAL.md"

# ---------------------------------------------------------------- oci + cost
say "oci"
if oci_select_profile >/dev/null 2>&1; then
  grab "$E/oci/limits-compute.json" oci_t limits value list --service-name compute --compartment-id "$OCI_TENANCY" --all
  grab "$E/oci/limits-block-storage.json" oci_t limits value list --service-name block-storage --compartment-id "$OCI_TENANCY" --all
  grab "$E/oci/budgets.json" oci_t budgets budget budget list --compartment-id "$OCI_TENANCY"
  ./scripts/cost-check.sh 30 > "$E/cost/summary.txt" 2>&1 && echo "  ok   $E/cost/summary.txt" || echo "  WARN cost-check failed"
else
  echo "  SKIP no working OCI session"
fi

say "done"
cat <<EOF
Review $E, take the Grafana screenshots listed in $E/grafana/MANUAL.md, then:

  git add docs/evidence && git commit -m "docs: capture evidence before teardown"
  ./scripts/down.sh

Do not run down.sh until the evidence is COMMITTED. It is not recoverable afterwards.
EOF
