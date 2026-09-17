# 9. Public Worker Subnet

## Status
Accepted

## Context
Workers can be placed in public subnets (with direct public IPs) or private subnets (behind NAT). Solana gossip participants must be reachable on UDP from arbitrary peers.

## Decision
Place workers in a PUBLIC subnet with direct public IPs.

## Consequences
**Gossip requirement is hard.** A gossip participant must advertise an address reachable from any peer on the internet. Private subnets with NAT violate this: the pod's internal address does not match peers' view of where to reach it. This causes connectivity failures.

**Contradicts cloud best practices.** Oracle's own OKE module documentation recommends "prefer private subnets." This decision intentionally deviates from that guidance, which is why it is recorded explicitly rather than left as a silent setting.

**Mitigated by tight security groups.** The public-subnet risk is contained:
- Only UDP ports 8000–8020 (P2P range) are open to 0.0.0.0/0
- SSH is scoped to a specific admin CIDR
- JSON-RPC port 8899 is not exposed; it binds to 127.0.0.1 only

**Trade-off: public surface.** The node has a public IP and is reachable from anywhere on the internet for P2P traffic. This is the price of validator participation.

**Accepted for this role.** Non-voting followers do not handle vote transactions. Attack surface is limited to consensus traffic that validators receive anyway.
