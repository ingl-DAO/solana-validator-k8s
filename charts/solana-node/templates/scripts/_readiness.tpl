{{- define "solana-node.readiness" -}}
#!/usr/bin/env bash
set -euo pipefail

# DO NOT use httpGet on getHealth.
#
# Two independent reasons:
#  1. getHealth returns HTTP 200 carrying a JSON-RPC *error body* (-32005 NodeUnhealthy) when the
#     node is behind. An httpGet probe sees 200 and passes. It would never fail.
#  2. Under Alpenglow (live on testnet now) RpcHealth::check() requires Votor to have observed a
#     finalization certificate and returns Unknown until then. An unstaked 4.2.x node on an
#     Alpenglow cluster may never report healthy by that measure at all.
#
# So compare slots directly. Threshold matches --health-check-slot-distance.

rpc() {
  curl -s -m 4 -X POST -H 'Content-Type: application/json' -d "$1" \
    http://127.0.0.1:{{ .Values.ports.rpc }}
}

tip=$(rpc '{"jsonrpc":"2.0","id":1,"method":"getMaxShredInsertSlot"}' | jq -r '.result // empty')
cur=$(rpc '{"jsonrpc":"2.0","id":1,"method":"getSlot","params":[{"commitment":"processed"}]}' | jq -r '.result // empty')

[[ -n "$tip" && -n "$cur" ]] || exit 1
(( tip - cur <= {{ .Values.validator.healthCheckSlotDistance }} ))
{{- end }}
