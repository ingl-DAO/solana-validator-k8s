# 1. Testnet Not Devnet

## Status
Accepted

## Context
Solana operates two public test clusters: testnet and devnet. Both are available for validator participation. Storage constraints on the OCI trial account limit the choice.

## Decision
Deploy a non-voting follower node on Solana testnet, not devnet.

## Consequences
**Fits storage budget.** Testnet full snapshot is 5.3 GB; devnet is 65.9 GB (measured via HTTP HEAD on official snapshot endpoints). OCI trial block-volume quota is 200 GB aggregate including boot volumes. Devnet does not fit within this limit.

**Runs stable software.** Testnet uses Agave 4.2.2 (latest stable release); devnet runs 4.3.0-rc.0 (release candidate). RCs carry higher operational risk.

**Stays compact long-term.** Testnet is periodically reset, so its accounts DB remains smaller and more predictable over time. Devnet's accounts grow without reset.

**Targets the right audience.** Testnet is where validator operations actually occur. Devnet targets program developers writing smart contracts. This deployment prioritizes validator infrastructure patterns, not program development.

**Trade-off: less bleeding-edge.** Testnet lags the development branch. For this platform's scope (production-readiness patterns, Kubernetes integration, observability), testnet stability outweighs cutting-edge features.
