# 8. Node Layer Tuning vs Privileged InitContainer

## Status
Accepted

## Context
The Solana validator requires elevated file descriptor limits and network sysctls. These can be applied at the node layer (cloud-init) or in the pod (privileged init container).

## Decision
Apply node sysctls and containerd rlimits via node-pool cloud-init, not a privileged InitContainer.

## Consequences
**Kubelet constraint is real.** Kubernetes has no pod-spec field for resource limits (rlimits). This has been an open issue (kubernetes/kubernetes#3595) since 2015. Containerd 1.8+ leaves LimitNOFILE unset, and containers inherit the soft limit of 1024, which is insufficient for Solana.

**Node-layer application is cleaner.** Cloud-init runs at node provisioning time, applies settings system-wide, and survives pod restarts. Privileged init containers must run on every pod startup.

**Pod Security policies are stricter.** A privileged DaemonSet alternative is available (nodeTuner.enabled=false in the chart) for clusters where you do not own the nodes. However, PodSecurity baseline and restricted policies reject privileged pods. Node-layer tuning avoids this conflict.

**Trade-off: node-level blast radius.** Node-layer settings affect all pods on the node, not just the validator. For single-validator deployments, this is acceptable.

**Documentation is in the chart.** The privileged DaemonSet is retained as an alternative for reference and for heterogeneous clusters.
