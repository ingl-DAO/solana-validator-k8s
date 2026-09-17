# Cost Report

## Overview

This document tracks modelled vs. actual infrastructure costs for the solana-validator-k8s testnet follower node on Oracle Cloud. All costs are in USD for a trial account with promotional discounts applied.

---

## Plan: Cost Modelling

### Variant A: Continuous Operation (22 days)

**Assumption:** Node pool runs 24/7 for 22 days without scaling.

| Component | Unit | Qty | Rate | Subtotal |
|-----------|------|-----|------|----------|
| Compute (VM.Standard.E3.Flex, 2 OCPU) | OCPU-hours | 22 × 24 × 2 = 1,056 | $0.067/OCPU-hr | $70.75 |
| Block Volume (200 GB) | GB-months | 6.67 | $0.017/GB-month | $0.11 |
| Load Balancer (NLB, 1 hour active) | LB-hour | 528 | $0.0125/LB-hour | $6.60 |
| Data Transfer (egress, ~500 MB/day) | GB | 11 | $0.0085/GB | $0.09 |
| OKE Control Plane (free tier) | cluster | 1 | $0.00 | $0.00 |
| Subnet + NSG (no charges) | — | — | — | — |
| **Variant A Total** | | | | **$77.55** |

### Variant B: Scheduled Scaling (scale pool to 0 off-hours) — CHOSEN

**Assumption:** Scale node pool to 0 when not collecting data (nights/weekends). Active 4 hours/day, 22 days.

| Component | Unit | Qty | Rate | Subtotal |
|-----------|------|-----|------|----------|
| Compute (VM.Standard.E3.Flex, 2 OCPU) | OCPU-hours | 22 × 4 × 2 = 176 | $0.067/OCPU-hr | $11.79 |
| Block Volume (200 GB) | GB-months | 6.67 | $0.017/GB-month | $0.11 |
| Load Balancer (NLB, no active use) | LB-hour | 0 | $0.0125/LB-hour | $0.00 |
| Data Transfer (egress, ~100 MB/active-day) | GB | 0.88 | $0.0085/GB | $0.01 |
| OKE Control Plane (free tier) | cluster | 1 | $0.00 | $0.00 |
| Subnet + NSG (no charges) | — | — | — | — |
| **Variant B Total** | | | | **$11.91** |

**Decision:** Variant B chosen. Use Kubernetes CronJob or manual scaling to reduce active time and minimize compute charges.

---

## Actuals

**Reporting Period:** TODO: [start date] to [end date]

| Date | Service | Component | Modelled (USD) | Actual (USD) | Delta (USD) | Notes |
|------|---------|-----------|---|---|---|---|
| TODO | Compute | VM.Standard.E3.Flex | TODO | TODO | TODO | TODO |
| TODO | Storage | Block Volume | TODO | TODO | TODO | TODO |
| TODO | Networking | Load Balancer | TODO | TODO | TODO | TODO |
| TODO | Networking | Data Transfer (egress) | TODO | TODO | TODO | TODO |
| | | **Actuals Subtotal** | | **TODO** | **TODO** | |

---

## How This Was Measured

**Data Source:** Oracle Cloud Infrastructure Usage API

**Command:**
```bash
oci usage-api request-summarized-usages \
  --tenant-id <TENANCY_ID> \
  --time-usage-started "2026-09-01T00:00:00Z" \
  --time-usage-ended "2026-09-22T23:59:59Z" \
  --granularity DAILY \
  --query-type AGGREGATED
```

**Processing:**
1. Extract cost-tracking tags applied to compute instances and volumes.
2. Filter by service (Compute, Storage, Networking) and resource tags (solana-validator, test, terraform).
3. Sum daily charges by service; compare to modelled rates.

**Discount Caveat:**
Trial account usage is subject to promotional pricing. Standard list rates do not apply. Actual costs shown above reflect the trial period discount. Post-promotion pricing will be higher and should be remodelled once the trial ends.

---

## Conclusion

**TODO:**
- Measure actual usage for the full 22-day period.
- Compare Variant B modelled ($11.91) to actual spend.
- Document any unexpected charges (e.g., reserved capacity, premium support, data transfer direction).
- If actual exceeds modelled by > 10%, investigate root cause and adjust layering assumptions.
- Baseline the cost per day of operation for future capacity planning.
