# 5. hostNetwork vs NLB vs NodePort

## Status
Accepted

## Context
The validator node must accept inbound gossip, turbine, and repair traffic on a wide UDP range from arbitrary peers. Kubernetes offers several networking modes.

## Decision
Use `hostNetwork: true` in the pod spec.

## Consequences
**Advertised address is real.** Solana peers learn the node's advertised address and must reach it directly. hostNetwork gives the pod the node's actual IP and port. NodePort remaps ports, breaking the advertised address that peers try to reach. This causes packet loss and connectivity failures.

**Handles UDP volume.** Cloud load balancers (NLB) do not handle Solana's UDP pattern well—thousands of concurrent peer connections sending across a wide port range strain load balancer tracking. Direct host access avoids this.

**Simple and fast.** No extra indirection layer. Packets arrive at the pod without translation overhead.

**Trade-off: one pod per node.** Cannot schedule multiple validator replicas per node, since each needs hostNetwork. This requires a separate node per replica.

**Trade-off: node firewall exposure.** The pod is bound by the node's host firewall. Any NSG rule that lets traffic in reaches the pod. Mitigated by tight security group rules: only P2P ports open to 0.0.0.0/0.
