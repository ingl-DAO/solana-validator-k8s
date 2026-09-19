# Grafana capture

The dashboard is committed as
[`charts/solana-node/dashboards/solana-node.json`](../../../charts/solana-node/dashboards/solana-node.json)
and loaded automatically by the Grafana sidecar (the ConfigMap carries the `grafana_dashboard: "1"`
label). **The JSON is the reproducible artifact; a PNG is not** — anyone can rebuild the view from
it, which a screenshot does not allow.

## Expect 12 of 21 metric panels to be empty, legitimately

The dashboard ships with `asymmetric-research/solana-exporter` and is built for a **voting
validator**. Measured against what this deployment actually emitted:

| | |
|---|---|
| `solana_*` metrics the dashboard queries | 17 |
| Metrics a non-voting follower emits in `-light-mode` | 10 |
| Panels that populate | **9** |
| Panels that stay empty forever | **12** |

The empty ones are all validator-identity panels — Validator Active Stake, Current SOL Balances,
Validator Vote Slack Distance, Block Production Rate, Root Slot Slack Distance. A follower has no
vote account, no stake and no balance, so there is nothing for them to show and never will be.

**Say this next to any screenshot.** A reviewer seeing half a dashboard empty will otherwise assume
the monitoring is broken, when it is reporting correctly about a node that does not vote.

The panels that do populate are the ones this project set out to observe: slot height, slots
behind, node health, epoch progress, transaction count, version.

## Capturing a screenshot worth showing

A dashboard over a 15-minute window reads as fake, and half-empty panels with no explanation read
as broken. If capturing:

- [ ] Time range **≥ 2h**, ideally 24h. The sync curve is the interesting part and it takes time to
      form.
- [ ] Template variables set to real values, not `All`.
- [ ] One visible incident you can explain — deleting the pod and letting it recover produces a
      genuine red-then-green on slot height.
- [ ] Crop to, or annotate, the 9 panels that populate.
- [ ] Save as `docs/evidence/grafana/*.png` and reference from the README.

Reproduce the stack with `make follower-local`, then:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

## Status

Not captured. The node reached full sync and the scrape chain was verified end to end
([RESULTS.md](../local/RESULTS.md)), but the cluster was torn down after ~1 hour rather than soaked
long enough for a time series worth photographing — 53 GB on a laptop root filesystem with no
quota enforcement was not worth the risk. The verification that matters is in `RESULTS.md`:
target `UP`, both relabelings present in the stored series, `solana_node_slot_height 442209566`.
