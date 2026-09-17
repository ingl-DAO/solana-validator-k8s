# Architecture

## Request Path

Internet traffic flows through the following layers:

```
Internet
  ↓
OCI Stateless Network Security Group (NSG)
  Ingress: UDP/TCP 8000-8026 (P2P gossip)
  ↓
Compute Instance Linux Kernel
  iptables filter/INPUT chain
  ↓
hostNetwork Pod (agave-validator)
  agave-validator process (port 8000-8026 P2P, 8899 JSON-RPC)
  └─ Metrics exporter sidecar
       └─ Reaches JSON-RPC on 127.0.0.1:8899 (shared host netns)
  ↓
Prometheus ServiceMonitor
  ↓
Grafana Dashboard
```

## Layering

The codebase splits into two independent layers:

| Layer | Path | Role | Scope |
|-------|------|------|-------|
| **Cloud Infrastructure** | `terraform/modules/oci-oke` | Disposable, OCI-specific provisioning (compute, networking, storage) | Oracle Cloud only |
| **Application Deployment** | `charts/solana-node` | Portable, cloud-agnostic Kubernetes deployment | Any K8s cluster with kubeconfig |

The seam between layers is defined by:
- **Contract:** `terraform/modules/README.md` specifies what OCI layer must provide (kubeconfig path, subnet CIDR, node labels, etc.)
- **Input:** `charts/solana-node/values.yaml` consumes the contract (cluster endpoint, node selectors, persistent volume paths)

This design allows `charts/solana-node` to run unmodified on any Kubernetes cluster (EKS, AKS, on-prem) once the OCI layer delivers the kubeconfig.

## Ports

| Port(s) | Protocol | Direction | Use | Exposure |
|---------|----------|-----------|-----|----------|
| 8000–8026 | UDP + TCP | Inbound | Solana P2P gossip | Public (NSG allows) |
| 8899 | TCP | Loopback | JSON-RPC (validator internal) | Never on wire; exporter accesses via 127.0.0.1:8899 |
| 8900 | TCP | Loopback | WebSocket (validator internal) | Not exposed |
| 8080 | TCP | VCN-internal | Metrics exporter (Prometheus scrape) | VCN subnet only |
| 22 | TCP | Inbound | SSH admin access | Admin CIDR only (OCI NSG restricted) |

## Network Flow Examples

**Incoming P2P packet (gossip):**
```
NSG rule: 8000-8026/UDP allow → iptables INPUT → pod receives → agave-validator processes
```

**Metrics collection (internal):**
```
Prometheus (outside cluster) → port 8080 on worker node → exporter Pod → 127.0.0.1:8899 → agave-validator JSON-RPC
```

## TODO
- Add actual observed MTU and packet loss baselines from production traffic capture.
- Document qdisc/tc traffic shaping rules if applied for P2P gossip rate-limiting.
