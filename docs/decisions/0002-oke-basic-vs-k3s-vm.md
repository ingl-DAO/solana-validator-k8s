# 2. OKE Basic vs k3s VM

## Status
Accepted

## Context
A Kubernetes cluster requires a control plane and workers. Options include managed Kubernetes (OKE) and self-managed k3s on a single VM.

## Decision
Use OCI Container Engine for Kubernetes (OKE) Basic tier with worker node pools.

## Consequences
**Zero control-plane cost.** OKE Basic charges $0/hr for the control plane; only Enhanced is $0.10/hr. Self-managed k3s on a VM costs the same as the VM itself.

**Cloud integration included.** OKE provides cloud-controller-manager and the OCI block-volume CSI driver, enabling declarative storage binding. k3s on a VM has neither and would require manual orchestration.

**Easy teardown.** `terraform destroy` reclaims the entire cluster. Self-managed VMs require explicit cleanup or the compute continues accruing charges.

**Trade-off: less control.** OKE abstracts the control plane. Node-level configuration (kernel settings, containerd limits) must be applied via cloud-init; cannot be customized at the apiserver or scheduler level.

**Operational complexity is lower.** Managed service eliminates patching, cert rotation, and etcd backups for the control plane. This tradeoff favors reliability over deep customization.
