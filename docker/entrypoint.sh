#!/usr/bin/env bash
# Thin wrapper. The actual flags live in the chart's ConfigMap so they are visible in
# `helm template` and reviewable in a diff, rather than buried in an image.
set -euo pipefail

# Printed before anything else. If these read 1024 / 64, the node-layer tuning did not land and
# the node will drop packets under turbine load. See terraform/modules/README.md §5,§6.
echo "[entrypoint] nofile=$(ulimit -n) memlock=$(ulimit -l) user=$(id -u)"

# Advertised-address strategy. Kept here, not in the chart, because it is the one genuinely
# provider-shaped concern in the container.
#   ipecho : do nothing — Agave resolves the address by IP-echo against --entrypoint. Correct for
#            1:1 NAT (OCI, AWS). Note --gossip-host was REMOVED in Agave 4.0 (PR #9058); the
#            recipe you will find in every blog post exits with an argument error.
#   imds   : read the public IP from the cloud metadata service and pass --advertised-ip, which
#            is hidden_unless_forced() and does not appear in --help.
case "${ADVERTISED_ADDRESS_STRATEGY:-ipecho}" in
  ipecho) ;;
  imds)
    ip=$(curl -fsS -m 3 -H "Authorization: Bearer Oracle" \
         http://169.254.169.254/opc/v2/vnics/ 2>/dev/null | jq -r '.[0].publicIp // empty') || true
    [[ -n "${ip:-}" ]] && export SOLANA_ADVERTISED_IP="$ip" && echo "[entrypoint] advertised-ip=$ip"
    ;;
  *) echo "[entrypoint] unknown ADVERTISED_ADDRESS_STRATEGY" >&2; exit 64 ;;
esac

exec "$@"
