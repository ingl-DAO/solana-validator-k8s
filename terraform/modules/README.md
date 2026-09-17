# The infrastructure contract

This directory holds **disposable, cloud-specific** infrastructure. The value of this repository
is not here — it is in [`charts/solana-node`](../../charts/solana-node), which contains no cloud
strings of any kind and runs unmodified on kind, OKE, EKS, GKE, k3s on a rented box, or bare metal.

The seam between the two layers is **the kubeconfig**. Everything below the seam is a rewrite per
provider. Everything above it is portable by construction, and is demonstrated to be so by
`make dev-up`, which runs the same chart on kind with no cloud credentials at all.

```
  terraform/modules/<provider>/     ~400 lines   rewritten per cloud   DISPOSABLE
  ──────────────────────────────────────────────────────────────────────────────
                       ↓ satisfies the contract below ↓
  ──────────────────────────────────────────────────────────────────────────────
  charts/solana-node/               portable     never touches a cloud API
```

There is no cross-cloud Terraform abstraction here, because there isn't one worth having.
`oci_core_vcn`, `aws_vpc` and `hcloud_network` are different resources with different semantics,
and the tools that claim to paper over that (Crossplane, Pulumi) still require provider-specific
compositions underneath. For a project this size, that machinery costs more than the rewrite it
saves. Portability comes from **where the seam is**, not from the tool.

## The contract

Any implementation in this directory must hand the chart the following. If it does, the chart
works. If it does not, the chart fails in one of the ways documented in
[`docs/runbook.md`](../../docs/runbook.md).

| # | Requirement | Why | Verify with |
|---|---|---|---|
| 1 | A conformant Kubernetes cluster, v1.29+ | StatefulSet, PDB `policy/v1`, `startupProbe` | `kubectl version` |
| 2 | A StorageClass with `allowVolumeExpansion: true`, `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Retain`, and **≥75 IOPS/GB** | The accounts DB write-amplifies; `Retain` is what lets the node pool scale to zero overnight without losing the ledger | `kubectl get sc -o yaml` |
| 3 | At least one node with a **routable public address** and inbound **UDP and TCP 8000–8026** from `0.0.0.0/0` | Gossip peers dial arbitrary ports in that range; the node must be reachable at the address it advertises | `tcpdump -ni any 'udp portrange 8000-8026'` |
| 4 | **1:1 NAT or a direct public IP** — not port-remapping NAT | Agave discovers its advertised address by IP-echo against an entrypoint; a remapped port makes that address wrong and peers unreachable | validator startup log |
| 5 | Node sysctls applied (`net.core.rmem_max`, `wmem_max` = 134217728, `vm.max_map_count` = 1000000, `fs.nr_open` = 1000000) **or** permission to run a privileged DaemonSet | A container cannot set these. Without them Agave drops packets under turbine load | `sysctl -a \| grep rmem_max` |
| 6 | Container runtime rlimits: `LimitNOFILE=1000000`, `LimitMEMLOCK=infinity` | Kubernetes has no pod-spec field for rlimits ([k/k#3595](https://github.com/kubernetes/kubernetes/issues/3595), open since 2015); containerd 1.8+ leaves `LimitNOFILE` unset so containers inherit soft 1024. Agave 3.0+ makes memlock a hard startup requirement | `cat /proc/<pid>/limits` |
| 7 | `seccompProfile: Unconfined` permitted by cluster policy | Agave ≥2.0 uses `io_uring` for snapshot unpack; `RuntimeDefault` blocks `io_uring_setup/enter/register`. The failure happens *during* unpack, not at process start | PodSecurity admission label |
| 8 | Egress to the internet on the same range | Snapshot fetch, entrypoint gossip, IP-echo | — |

Requirement **7** is the one that will bite on a managed cluster with PodSecurity `restricted`
enforced. There is no workaround short of a policy exemption.

## What is NOT in the contract

Deliberately. These are the provider's business, and the chart must never assume them:

- **How the public address is obtained.** OCI uses 1:1 NAT with the IP discovered by IP-echo. AWS
  would use the same mechanism against a different IMDS. Bare metal has a real address and needs
  neither. `docker/entrypoint.sh` keeps this behind a strategy switch (`ipecho` by default).
- **How the host firewall is opened.** Oracle's images terminate `filter/INPUT` with
  `REJECT --reject-with icmp-host-prohibited`, so the OCI module inserts ACCEPT rules with
  `iptables -I` (never `-A`). AWS images have no such rule and need nothing. This is why the
  firewall logic lives in `oci-oke/cloud-init/`, not in the chart.
- **Stateless vs stateful firewall rules.** An OCI-specific concern — see
  [ADR 0006](../../docs/decisions/0006-stateless-nsg-and-vnic-conntrack.md).
- **StorageClass parameters.** `vpusPerGB` is an OCI concept. The chart takes
  `persistence.storageClassName` as a value and never defines a StorageClass.
- **LoadBalancer annotations.** Not used at all. The node is on `hostNetwork`; there is no
  LoadBalancer to annotate, which removes an entire category of cloud coupling.

## Implementations

| Directory | Provider | Status |
|---|---|---|
| [`oci-oke/`](oci-oke/) | Oracle Cloud, OKE Basic + one E4.Flex worker | Built and torn down; evidence in [`docs/evidence/`](../../docs/evidence/) |
| `../local/` | kind / k3d, `mode: test-validator` | Permanent. Needs no credentials. This is the portability proof |

## Porting this to another cloud

1. Implement the eight contract requirements. Expect ~400 lines and one evening.
2. Point `charts/solana-node` at the new StorageClass via `persistence.storageClassName`.
3. Pick an advertised-address strategy in `values.yaml` if IP-echo does not suit the provider.
4. Change nothing else.

**One honest caveat.** The contract keeps the *chart* portable. It does not make the *operational
knowledge* portable. The UDP debugging in [`docs/runbook.md`](../../docs/runbook.md) is
OCI-flavoured; on AWS you would fight security groups and a different metadata endpoint instead.
One `terraform apply` does not move you between clouds, and this repo does not claim it does.

## Hybrid

For this workload hybrid is the realistic end state, not a hypothetical: every serious operator
(Helius, Triton, Blockdaemon) runs Solana on bare metal. The node goes where the hardware is; the
monitoring and control plane live wherever is convenient. The chart supports that with
`nodeSelector` and `affinity` and nothing else — the same mechanism that pins the node to the one
worker with the fast volume attached.
