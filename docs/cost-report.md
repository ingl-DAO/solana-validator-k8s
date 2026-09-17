# Cost report

Modelled vs actual spend for the testnet follower on Oracle Cloud.

## Starting position — verified

| | |
|---|---|
| Checked | 2026-09-18 (day 9 of the 30-day trial) |
| Console → Billing → Credits | **€0.00 / €250.00** |
| Spent so far | **€0.00** — the full allowance is intact |
| Currency | **EUR**, not USD |

This refutes the earlier working assumption that €250 on day 8 meant a remaining balance after
~€50 of burn. Nothing has been spent. It also means **money is not the binding constraint on this
project** — the calendar and the service limits are. See the note on the OCPU limit below, which
is the one place where that stops being true.

The modelled figures below are **USD list PAYG** rates from Oracle's pricing API (lastUpdated
2026-09-09). Actuals will bill in EUR, and trial usage is discounted during the promotional
period, so burn will not track list-price arithmetic. Compare against the console, not this table.

## Modelled

Shape: `VM.Standard.E4.Flex`, 6 OCPU / 64 GB. Storage at 730 hr/month.
There is **no load balancer** in this architecture — the node runs on `hostNetwork`, which removes
that line item entirely along with a category of cloud coupling.

### Variant A — leave it up for the remaining 22 days

| Line item | Unit price | Qty | Days | Total |
|---|---|---|---|---|
| E4.Flex OCPU | $0.025/OCPU-hr | 6 | 22 | $79.20 |
| E4.Flex memory | $0.0015/GB-hr | 64 | 22 | $50.69 |
| Boot volume, Balanced 10 VPU | $0.0425/GB-mo | 60 GB | 22 | $1.87 |
| Ledger volume, Higher Perf 20 VPU | $0.0595/GB-mo | 100 GB | 22 | $4.36 |
| OKE Basic control plane | $0 | 1 | 22 | $0.00 |
| Egress | free < 10 TB/mo | — | — | $0.00 |
| **Total** | | | | **$136.12** |

### Variant B — scale the node pool to 0 between sessions — CHOSEN

| Line item | Unit price | Qty | Hours | Total |
|---|---|---|---|---|
| Compute, 4 build sessions × 5 h | $0.246/hr | 1 node | 20 | $4.92 |
| Compute, one deliberate 24 h soak | $0.246/hr | 1 node | 24 | $5.90 |
| Boot volume (exists only while the node does) | $0.0425/GB-mo | 60 GB | 44 | $0.16 |
| Ledger volume, retained 15 days to avoid re-sync | $0.0595/GB-mo | 100 GB | 360 | $2.98 |
| OKE Basic control plane | $0 | — | — | $0.00 |
| **Total** | | | | **$13.96** |

Plus a one-off ephemeral build VM (E4.Flex 6/64, 100 GB boot, ~2 h) at roughly **$0.50**. Delete it
the same evening — its 100 GB boot volume competes with the ledger for the block-volume quota.

**Delta: $122.16.** `make pause` / `make resume` are Variant B.

### Why Variant B, given the headroom

$13.96 against €250 leaves ~95% unused, so the choice is not financial. Scaling to zero between
sessions is chosen because it is the defensible engineering habit and because `reclaimPolicy:
Retain` on the ledger volume makes it free of consequence. What the headroom genuinely buys is a
**longer soak** — the 24 h in the model is a floor, not a budget ceiling, and more continuous
time-series makes the Grafana evidence materially better.

### Where money could become the constraint

The 6 OCPU cap is a **service limit**, not a price. But if the limit-increase request to 16 OCPU is
approved, it unlocks something the plan wrote off: **Ultra High Performance block storage requires
multipath attachment, which requires ≥16 OCPU.** At 6 OCPU it is unreachable at any price. At 16 it
becomes a purchasing decision, and one this balance can absorb. That makes the limit-increase
request worth chasing rather than filing and forgetting.

## Actuals

| Date | Service | Modelled | Actual (EUR) | Delta | Note |
|---|---|---|---|---|---|
| 2026-09-18 | — | — | €0.00 | — | Baseline. Nothing provisioned yet. |
| | | | | | |

## How this was measured

```bash
oci usage-api request-summarized-usages \
  --tenant-id "$OCI_TENANCY" \
  --time-usage-started "$(date -u -d '7 days ago' +%Y-%m-%dT00:00:00Z)" \
  --time-usage-ended   "$(date -u +%Y-%m-%dT00:00:00Z)" \
  --granularity DAILY --query-type COST
```

Wrapped by `make cost` (`scripts/cost-check.sh`). Daily dumps land in `docs/evidence/cost/`.

## Conclusion

TODO — fill in after teardown: modelled total, actual total, the delta and its explanation, and
the credit left unused. "Estimated $X/day, ran Variant B, spent €Y, left €Z unused" is the line
that demonstrates cost discipline, which is worth more than the number itself.
