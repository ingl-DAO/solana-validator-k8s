# Custom Checkov policies

Generic IaC scanners do not know what this workload needs, and on several points they are wrong
about it. These policies encode the project's own rules so CI enforces them, and the suppressions
below record where a generic rule was rejected and why.

> **`__init__.py` is load-bearing.** Checkov silently skips any external-checks directory without
> one — it logs `Cannot load any check here` at INFO level, so by default the scan looks clean and
> the checks never run. Do not delete it.

## The policies

| Policy | Rule | Why |
|---|---|---|
| `CKV_SOLANA_1` | No ingress rule may open **8899** or **8900** to `0.0.0.0/0` | JSON-RPC binds to `127.0.0.1`; the exporter reaches it over loopback in the shared host netns. The port should never appear in a security rule at all. An open Solana RPC endpoint is a documented abuse vector. |
| `CKV_SOLANA_2` | Rules touching **8000–8026** must be `stateless = true` | OCI enforces stateful rules with a per-VNIC connection-tracking table sized by shape. Solana's UDP volume from thousands of peers fills it, producing symptom-free packet loss with no error anywhere. See [ADR 0006](../docs/decisions/0006-stateless-nsg-and-vnic-conntrack.md). |

Both are verified against a deliberately-violating fixture, not just against passing code — a
policy that never fires is worse than no policy.

## Findings triage

A full scan produced 8 findings. Two were real and were **fixed**; six were generic rules that are
wrong for this workload and are suppressed inline, each with a reason.

### Fixed

| Check | What it caught | Fix |
|---|---|---|
| `CKV2_OCI_5` | Node pool block volumes had no in-transit encryption | `is_pv_encryption_in_transit_enabled = true`. Free, correct, no reason not to. |
| `CKV2_OCI_3` | The cluster's public API endpoint had no NSG | Added an API NSG scoping 6443 to `admin_cidr` and the VCN. A genuine improvement the scanner was right about. |

### Suppressed, with reasons

| Check | Where | Why rejected |
|---|---|---|
| `CKV_OCI_21` — "ingress rules must be stateless" | `ssh_in`, `exporter_in`, `api_in`, `api_workers_in` | **Too blunt.** Stateless is a *mitigation for conntrack exhaustion under Solana's P2P UDP volume*, not a general good. A 15-second Prometheus scrape, SSH from one CIDR, and kubectl sessions cannot exhaust the table — and stateless would force a companion egress rule for each, for no benefit. Applied deliberately to the P2P range only. |
| `CKV2_OCI_2` — "no traffic on RDP 3389" | 4 **egress** rules | The check matches egress rules by shape rather than by port. Nothing can reach the node on RDP; egress is required for snapshot fetch, gossip and image pulls. |
| `CKV2_OCI_6` — "pod security policy enforced" | cluster | **Obsolete.** PodSecurityPolicy was deprecated in Kubernetes 1.21 and removed in 1.25. This cluster runs 1.31, where the resource does not exist. Its successor, Pod Security Admission, is enforced by namespace label and not by cluster config. |

The `CKV_OCI_21` case is the interesting one, and the reason a custom policy exists at all: the
built-in demands stateless everywhere, which is both more than needed and a misreading of *why*
stateless matters here. `CKV_SOLANA_2` enforces it precisely where it is load-bearing.

## Running it

```bash
make policy          # custom checks only
make security        # full scan, external checks included
checkov -d terraform/ --external-checks-dir policies --compact
```

Current state: **37 passed, 0 failed, 9 skipped.**
