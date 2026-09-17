# 10. E4 Not E5 Shape Selection

## Status
Accepted

## Context
OCI trial accounts have per-shape-family compute limits. Compute shapes E4, E5, and E6 are available. Each family has different resource limits, pricing, and microarchitecture.

## Decision
Use VM.Standard.E4.Flex 6 OCPU / 64 GB RAM configuration.

## Consequences
**Service limit is largest.** E4's trial service limit bucket is 6 OCPU / 96 GB, while E5 and E6 are limited to 6 OCPU / 72 GB. E4 offers the most available RAM.

**More RAM available.** 64 GB RAM is ample for a non-voting follower. Larger pools can consume up to 64+ GB.

**Lower cost.** E4 is $0.025/OCPU-hr + $0.0015/GB-hr vs E5's $0.030 + $0.002. E4 is significantly cheaper.

**Higher base clock.** E4 (EPYC 7J13 Milan) runs at 2.55 GHz vs Genoa 2.4 GHz. Higher clock speeds help with single-threaded consensus work.

**Does not meet mainnet bar.** Note that none of these shapes meet Anza's published 2.8 GHz recommendation for mainnet validators. This deployment targets testnet only.

**Fallback order defined.** E4 → E6 → E5, allowing the automation to gracefully degrade if E4 capacity is exhausted.

**Optimal for trial constraints.** E4 maximizes available resources within OCI trial limits while minimizing cost.
