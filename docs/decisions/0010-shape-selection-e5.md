# 10. Shape selection: E5, not E4

## Status

**Superseded by measurement, 2026-09-18.** The original decision (E4 over E5) was made from
Oracle's published trial limit buckets and is wrong for this tenancy.

## Context

The original reasoning: `VM.Standard.E4.Flex` has a trial limit bucket of 6 OCPU / 96 GB while E5
and E6 are 6 / 72 GB; E4 is cheaper ($0.025/OCPU-hr + $0.0015/GB-hr vs E5's $0.030 + $0.002) and
has a higher base clock (EPYC 7J13 Milan 2.55 GHz vs Genoa 2.4 GHz). More RAM, more clock, less
money.

That reasoning was sound and the premise was false. Querying the actual tenancy
(`oci limits value list --service-name compute`, eu-frankfurt-1, all three ADs):

| Limit | Value |
|---|---|
| `standard-e5-core-count` / `-memory-count` | **13 / 208 GB** |
| `standard-e3-core-ad-count` / `-memory-count` | 16 / 277 GB |
| `standard-e2-core-count` | 13 |
| `standard-a1` / `a2` / `a4` core counts | 41 / 29 / 6 |
| **`standard-e4-core-count`** | **0** |
| `standard-e6-core-count` | 0 (only `-reserved-` is non-zero) |

E4 is not capped at 6. It is **unavailable**: a limit of 0 in every AD. No E4 instance can be
launched at any size.

The ARM shapes (A1/A2/A4) have generous limits and are unusable regardless — no `linux/aarch64`
Agave binary has ever been published, and Anza requires AVX2 + SHA extensions (ADR 0004).

## Decision

**`VM.Standard.E5.Flex`, 8 OCPU / 96 GB.** Fallback `VM.Standard.E3.Flex` (16 / 277 available),
then E2.

8 of the 13 available OCPUs, not the maximum. At 13/208 the burn is roughly $19.4/day, which over
the remaining trial would exceed the credit balance. 8/96 is roughly $10.4/day and is already well
clear of what an Agave testnet follower needs — the original plan assumed 6/64 would do.

## Consequences

- More capacity than planned, not less: 8 OCPU / 96 GB against the 6 / 64 the design assumed.
- Higher hourly rate, so `make pause` / `make resume` stop being tidiness and become the mechanism
  that keeps the project inside its credits.
- E5 at 13 OCPU is below the 16 required for multipath block volume attachment, so Ultra High
  Performance storage stays out of reach unless a limit increase is granted. E3 already has 16,
  which may make UHP reachable today on the fallback shape — unverified.
- **Generalised lesson, and the one worth repeating in the README:** published limit tables
  describe a notional account. Query the tenancy. Two of this plan's load-bearing constraints were
  wrong in opposite directions, and one command surfaced both.
