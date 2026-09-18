#!/usr/bin/env bash
# Provision the cluster and deploy the node, end to end.
#
#   ./scripts/up.sh                 # full: terraform + monitoring + node
#   ./scripts/up.sh --infra-only    # terraform + kubeconfig, nothing on the cluster
#   ./scripts/up.sh --skip-infra    # cluster already up; just (re)deploy the charts
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_DIR="terraform/envs/oci-testnet"
RELEASE="solana"
NS_MON="monitoring"
KPS_VERSION="${KPS_VERSION:-91.4.1}"
CHART="charts/solana-node"
VALUES="${VALUES:-$CHART/values-testnet-follower.yaml}"

INFRA=1; CHARTS=1
case "${1:-}" in
  --infra-only) CHARTS=0 ;;
  --skip-infra) INFRA=0 ;;
  "") ;;
  *) echo "usage: $0 [--infra-only|--skip-infra]"; exit 64 ;;
esac

# The state backend needs these, and so do the checksum workarounds. Sourcing is not optional:
# without it `terraform init` fails on credentials and the state write fails on chunked encoding.
[[ -f terraform/.s3-credentials ]] || { echo "Missing terraform/.s3-credentials. Run ./scripts/bootstrap-state.sh"; exit 1; }
set -a; source terraform/.s3-credentials; set +a

if (( INFRA )); then
  echo "==> terraform"
  terraform -chdir="$ENV_DIR" init -backend-config=backend.hcl -input=false >/dev/null
  terraform -chdir="$ENV_DIR" apply -auto-approve -input=false

  echo "==> kubeconfig"
  eval "$(terraform -chdir="$ENV_DIR" output -raw kubeconfig_command)"
fi

kubectl cluster-info >/dev/null || { echo "No reachable cluster. Run without --skip-infra."; exit 1; }

echo "==> waiting for a Ready node"
kubectl wait --for=condition=Ready node --all --timeout=10m

if (( CHARTS )); then
  echo "==> kube-prometheus-stack $KPS_VERSION"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --version "$KPS_VERSION" \
    --namespace "$NS_MON" --create-namespace \
    -f deploy/monitoring/kube-prometheus-stack-values.yaml \
    --wait --timeout 15m

  echo "==> solana-node"
  # The identity keypair is generated once and kept in the cluster. A follower does not vote, so
  # this identity signs nothing of value — but it must be STABLE, because it is the node's gossip
  # identity and peers cache it.
  if ! kubectl get secret "${RELEASE}-solana-node-identity" >/dev/null 2>&1; then
    echo "    generating node identity"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    docker run --rm -v "$tmp:/out" "$(yq -r '.image.repository' "$CHART/values.yaml" 2>/dev/null || echo ghcr.io/marcjazz/agave):4.2.2" \
      solana-keygen new --no-bip39-passphrase -s -o /out/identity.json >/dev/null 2>&1 \
      || solana-keygen new --no-bip39-passphrase -s -o "$tmp/identity.json" >/dev/null
    kubectl create secret generic "${RELEASE}-solana-node-identity" --from-file=identity.json="$tmp/identity.json"
    echo "    identity: $(solana-keygen pubkey "$tmp/identity.json" 2>/dev/null || echo '(install solana CLI to print)')"
  fi

  helm upgrade --install "$RELEASE" "$CHART" -f "$VALUES" --wait --timeout 20m
fi

cat <<EOF

up.

  kubectl get pods -o wide
  kubectl logs sts/${RELEASE}-solana-node -c validator -f
  kubectl port-forward -n $NS_MON svc/kube-prometheus-stack-grafana 3000:80

Grafana admin password:
  kubectl get secret -n $NS_MON kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d

The node will be NOT READY for a while — it fetches a snapshot, unpacks it and replays before
JSON-RPC binds. That is expected; the startupProbe allows 2h. Do not restart it to "fix" this:
every restart costs another snapshot fetch.

WHEN YOU STOP WORKING:  make pause
EOF
