# 7. Single Node Pool Storage Arithmetic

## Status
Accepted

## Context
OCI trial accounts have a 6-OCPU limit per shape family. Two node pools of different shapes could increase total CPUs to 12 OCPU. Storage quota is 200 GB aggregate, including boot volumes.

## Decision
Use a single node pool with one E4.Flex node shape rather than multiple pools to spread the CPU limit.

## Consequences
**Storage arithmetic wins.** OCI's minimum block-volume size is 50 GB. A second node pool requires a second boot volume (50–60 GB). This leaves only 90 GB for the ledger PVC with zero expansion headroom. Single node: 60 GB boot + 100 GB ledger = 160 GB, leaving 40 GB for in-place PVC expansion as the ledger grows.

**Simplicity over raw capacity.** One node pool is easier to manage and reason about. The 6-OCPU constraint is sufficient for a non-voting follower; validators do not require mainnet-grade compute.

**Headroom is critical.** Ledger PVCs cannot be shrunk, only expanded. Headroom prevents the cluster from becoming full and unable to resize volumes.

**Trade-off: CPU ceiling.** Cannot scale beyond 6 OCPU per shape family. Mainnet validators require 8+ OCPU. For testnet, 6 OCPU is adequate.

**Verified against real usage.** Solana validators on testnet run comfortably on 4–6 OCPU. The trade-off is acceptable for this trial deployment.
