# 6. Stateless NSG and VNIC Conntrack

## Status
Accepted

## Context
OCI Network Security Groups (NSG) can be configured as stateful (default) or stateless. Solana validators generate high UDP traffic volume from many peers.

## Decision
Configure NSG rules for the P2P range (ports 8000-8020) as STATELESS.

## Consequences
**Prevents silent packet loss.** Stateful NSG rules use a per-VNIC connection-tracking table sized by the node shape. Solana's UDP volume from thousands of concurrent peers fills this table, causing packets to be silently dropped—no errors logged anywhere, just disappearing packets.

**Oracle's explicit recommendation.** Oracle documentation recommends stateless rules for high-volume internet-facing traffic. This is the prescribed pattern for Solana's gossip protocol.

**Trade-off: companion EGRESS rule required.** A stateless INGRESS rule alone is insufficient. Replies from the node will be dropped unless a corresponding stateless EGRESS rule permits responses. This is non-obvious and documented in 0006 to prevent the mistake.

**Everything else stays stateful.** SSH, JSON-RPC, and other low-volume rules remain stateful for simplicity. Only the high-volume P2P range requires this tuning.

**Verified at scale.** This pattern is standard practice in production Solana deployments on cloud infrastructure.
