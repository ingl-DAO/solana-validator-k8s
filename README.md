# solana-validator-k8s

A Kubernetes/Helm/Prometheus platform for a **Solana testnet node**. The node is a **non-voting
follower** — not a mainnet validator, and
[§ What would change for mainnet](#what-would-change-for-mainnet) says exactly why not.

This is a platform-engineering project applied to a Solana workload. The interesting parts are the
UDP networking, the measured resource envelope, and a Kubernetes layer that is portable across
clouds because the cloud-specific layer is deliberately disposable.

**A real Agave 4.2.2 node reached full sync under this chart** — `getHealth: ok`, 33 slots behind
tip, Prometheus scraping it with labels intact. Measurements in
[§ Measured results](#measured-results); raw artifacts in
[`docs/evidence/local/`](docs/evidence/local/RESULTS.md).

> **Status, honestly.** The Kubernetes layer is **proven**: a real testnet node synced under it and
> the full observability chain was verified end to end. The **OCI layer is written, validated and
> never applied** — an Oracle free trial cannot launch paid compute at all, whatever the credits
> say ([ADR 0012](docs/decisions/0012-trial-cannot-launch-paid-compute.md)). The network, NSGs and
> OKE cluster applied cleanly before that wall; the node pool did not.

## Run it in 5 minutes, with no cloud account

```bash
make dev-up      # kind + solana-test-validator, no credentials, no hostNetwork
make dev-down
```

That is the same chart that runs the testnet follower, in `mode: test-validator`. It is also the
portability proof — see [the infra contract](terraform/modules/README.md).

## Measured results

Agave 4.2.2 on kind, on a 12-core / 14 GB laptop, synced to Solana testnet.

```
READY   STATUS    RESTARTS   getHealth   lag
2/2     Running   0          "ok"        33 slots
```

**Memory — peak 6.69 GiB**, with `--accounts-index-limit minimal`:

| Phase | Memory |
|---|---|
| Snapshot download | ~1.2 GiB |
| **Accounts index generation** | **6.69 GiB — peak** |
| Bank loading | ~3.4 GiB |
| Steady state, synced | ~5.5–6.5 GiB |

Roughly **1/40th** of Anza's 256 GB mainnet guidance. The peak is a **startup transient**, not the
steady state — size a pod on observed steady-state memory and it OOMs on its next restart, giving
you a workload that runs fine until it reboots.

**Disk — 53 GB after one hour:** accounts 33 GB, ledger 15 GB, snapshots 5 GB. Accounts dominates
early, which is not the split the planning estimates assumed.

**Time to sync:** ~45 minutes cold start to `Ready`, most of it a 5.3 GB snapshot fetch at
6.4 MB/s plus an index build across 94,724 slots.

**The observability chain, verified rather than assumed:**

```
serviceMonitor/default/solana-solana-node/0   health: UP
app=solana   hostname=solana-dev-control-plane   lastError: (none)
solana_node_slot_height 442209566
```

Both relabelings present in the *stored series*, not merely configured. Without them every panel
and all six alert rules return "No data" with no error anywhere.

## Layout

```
charts/solana-node/          portable. no cloud strings. THE ASSET.
terraform/modules/oci-oke/   disposable. ~400 lines. rewritten per cloud.
terraform/modules/README.md  THE CONTRACT between the two.
terraform/local/             kind. the portability proof.
docker/                      the image. amd64 only, and the Dockerfile explains why.
docs/decisions/              11 ADRs.
docs/evidence/               what survives the trial expiring.
```

The seam between the two layers is the kubeconfig. Rewriting the bottom half for AWS is a day;
rewriting the top half is never, because it never touches a cloud API.

## What I found that the internet has wrong

Most of what is written about running Solana in containers describes a version that no longer
exists, or a default that is wrong outside mainnet. Every item here cost time to discover, and
each is reproducible from this repo.

### The three worth reading even if you never touch Solana

**`--restricted-repair-only-mode` no longer starts on an Alpenglow cluster.** It is *the*
documented fallback for a node that cannot accept inbound connections, and it is what this repo's
own runbook recommended. On Agave 4.2.2 against testnet it fails after the full snapshot download
and index build — about 25 minutes in — with:

```
INFO  local alpenglow address: 0.0.0.0:8011
ERROR Failed to start validator: Invalid QUIC address for Alpenglow BLS
```

Repair-only suppresses advertising; Alpenglow then has no address to derive its QUIC endpoint
from, falls back to the bind address, and rejects it. The error names QUIC, not the flag that
caused it.

**A `tcpSocket` probe can never pass against a loopback-bound service.** This chart binds RPC to
`127.0.0.1` on purpose — an open Solana RPC endpoint is a documented abuse vector, and not
listening beats a firewall rule. But kubelet dials probes from *outside* the container, at the pod
IP (the node IP under `hostNetwork`), so the probe is refused forever while the node is perfectly
healthy:

```
Startup probe failed: dial tcp 172.20.0.2:8899: connect: connection refused
```

The trap is that the exporter sidecar reaches the same port over loopback without trouble, because
containers in a pod share a network namespace — kubelet does not. "The sidecar can reach it" tells
you nothing about whether a probe can. `exec` probes run inside the container and work; `tcpSocket`
and `httpGet` do not.

**Two correct flags, jointly fatal: `--only-known-rpc` and the snapshot speed floor.**

The chart passes `--only-known-rpc` with three `--known-validator` pubkeys. That restricts snapshot
and RPC fetches to those operators only. It is the right posture: a snapshot *is* the state you
start from, so downloading one from an arbitrary peer means trusting a stranger's view of the
ledger. For a validator with stake at risk, it is the difference between joining the real chain and
joining someone's fork.

Separately, Agave aborts any snapshot download slower than `--minimal-snapshot-download-speed`
(10 MB/s) and gives up after `--maximum-snapshot-download-abort` (5) attempts. Also right on its
own terms: a snapshot fetched too slowly leaves more slots to replay than you can catch up on, so
failing fast beats discovering non-convergence an hour later.

Together they guarantee failure on a domestic connection. `--only-known-rpc` collapses the peer
pool from hundreds to three — often to *one*, since not all of them hold a recent snapshot — and
the speed floor then applies to that single pinned peer with nowhere better to retry to. Observed
here: **361 KB/s**, 28× below the floor, five aborts burned in seven minutes after downloading
2.2 GB, one attempt from failing outright. A 10 MB/s demand is reasonable of *the best of 300
peers* and unreasonable of *one specific peer you have pinned yourself to*.

Neither flag is wrong. The composition is. This repo keeps `--only-known-rpc` — the trust posture
is correct and a testnet re-sync costs nothing — and lowers the floor to 128 KB/s with 30 retries
instead. The generalisable shape is the same one the probe bug had: **two individually correct
decisions whose interaction nobody tested**, and the failure names neither of them.

### Agave defaults tuned for someone who is not you

Three, all correct for a mainnet operator with money at stake, all wrong for a testnet follower:

| Default | Consequence here |
|---|---|
| `--accounts-index-limit unlimited` | Keeps the entire accounts index resident. OOMs anything that is not a 256 GB box. |
| XDP transmit **on** | Needs `CAP_NET_RAW` + `CAP_NET_ADMIN`. With capabilities dropped, the validator binds every socket, contacts IP-echo, *then* exits. A follower transmits almost nothing, so XDP buys it nothing. |
| 10 MB/s snapshot floor, 5 aborts | Covered above — even a healthy 6.4 MB/s is below the floor, and `--only-known-rpc` removes anywhere better to retry to. |

The question worth asking of any default in infrastructure you did not write: **who is this
protecting, and am I them?**

### The rest

- **`agave-validator` has not shipped in the release tarball since Agave 3.0.** Anza's own v3.0.2+
  release notes say so. Every tutorial doing `curl release.anza.xyz/... | tar x && ./bin/agave-validator`
  is describing ≤2.3. Verified across four versions: v2.1.21 (100 entries), v2.3.11 (40), v3.0.8,
  v4.2.2 (17).
- **`cargo-install-all.sh --validator-only` is deprecated in 4.2.2 and is not validator-only.**
  It still builds every end-user and DCOU binary.
- **Testnet is 12× cheaper to bootstrap than devnet** — 5.3 GB vs 65.9 GB of snapshot, measured.
  That inverts the usual assumption that devnet is the small one.
- **`--gossip-host` was removed in Agave 4.0** (PR #9058). Its replacement, `--advertised-ip`, is
  `hidden_unless_forced()` and does not appear in `--help`.
- **`--dynamic-port-range` has a minimum width of 26 since 4.1.** The `8000-8020` in essentially
  every firewall guide is now a startup error.
- **No `linux/aarch64` Agave binary has ever been published**, for any version — and Anza requires
  AVX2 + SHA extensions on top. ARM is not a "build it yourself" path, it is a dead end.
- **The OCI trial's binding constraint is service limits, not price.** 6 OCPU per shape family per
  AD, and 200 GB of block volume *including boot volumes*, with a 50 GB per-volume minimum.

## Building the image

`agave-validator` is not distributed as a binary, so it is compiled here. **18.1 minutes** on a
12-core / 14 GB laptop at `-j6`, producing a 499 MB image.

Pin the toolchain from the tag you are building — `cargo install` does **not** read
`rust-toolchain.toml`, and a mismatch fails ~18 minutes in with `E0133` errors in `solana-core`
rather than anything that names the compiler:

```bash
curl -sL https://raw.githubusercontent.com/anza-xyz/agave/v4.2.2/rust-toolchain.toml   # 1.96.1
```

Full record, including the verified tarball listing, in
[docs/evidence/build/](docs/evidence/build/tarball-contents.md).

## Observability

Agave exposes **no Prometheus endpoint**. A repo-wide search for `prometheus` in `anza-xyz/agave`
returns zero hits; `metrics/` posts InfluxDB v1 line protocol to a single destination, which SFDP
requires to be `metrics.solana.com`, so it cannot cleanly be teed. RPC polling via
[`asymmetric-research/solana-exporter`](https://github.com/asymmetric-research/solana-exporter) is
therefore the architecture, not a workaround. (Firedancer, by contrast, does ship native
Prometheus on `[tiles.metric] prometheus_listen_port`, documented as diagnostic-only.)

## Cost

| Variant | Approach | Total |
|---|---|---|
| A | Leave it running 22 days | $136.12 |
| **B** | **Scale the node pool to 0 between sessions** | **$13.96** |

Variant B is what `make pause` / `make resume` do.

**Actual spend: €0.00.** The OCI layer never launched compute — a free trial cannot, whatever the
credit balance says ([ADR 0012](docs/decisions/0012-trial-cannot-launch-paid-compute.md)). The
network, NSGs, budget guardrail and OKE cluster all applied cleanly and cost nothing; the node
pool was refused. Details in [docs/cost-report.md](docs/cost-report.md).

## What would change for mainnet

The section that matters most, and the reason this repo does not overclaim.

Anza's mainnet bar is 2.8 GHz base with SHA extensions and AVX2, 12c/24t for a validator or
16c/32t for RPC, **256 GB RAM** (512 GB for RPC with all indexes, ECC), and NVMe with accounts
≥1 TB, ledger ≥1 TB and snapshots ≥500 GB **on separate spindles**, plus ≥2 Gbit/s staked.

This demo ran 6 OCPU / 64 GB with **one** 100 GB network block volume — roughly 4× short on RAM
for testnet and ~20× short of the mainnet spec, on shared storage rather than separate NVMe. None
of OCI's AMD flex shapes even meet the base-clock line: E4 is 2.55 GHz, E6 2.7 GHz, E5 2.4 GHz.
Mainnet bootstrap is 120.6 GB of snapshot against testnet's 5.3 GB.

Ultra High Performance block storage is *unreachable on any shape provisionable here*: it requires
multipath attachment, which requires ≥16 OCPU. That is a capability gate, not a budget one, and it
is the arithmetic behind not attempting a mainnet accounts DB on cloud block storage at all.

Operationally, mainnet differs in kind and not degree: restarts are coordinated cluster events with
hard-fork slots, not `kubectl delete pod`; upgrades are staggered by stake and coordinated out of
band, which is why `updateStrategy: OnDelete` is set here; HA is gossip-based identity failover,
not replica count, because two pods sharing an identity keypair double-sign; delinquency starts at
128 slots behind and recovery is a full snapshot refetch; and essentially every competitive mainnet
validator runs Jito-Solana with a relayer, block engine and tip-distribution account — an entirely
separate operational surface this repo does not touch.

See [LIMITATIONS.md](LIMITATIONS.md) for the honest list, including the fact that Anza states
plainly that running Agave in Docker for live clusters is not supported, and that Anza's own
Kubernetes project `anza-xyz/validator-lab` was archived in February 2026.

## Related

[**ingl-DAO/permissionless-validators**](https://github.com/ingl-DAO/permissionless-validators) —
the on-chain counterpart. A native Solana program (no Anchor) that fractionalizes validator
creation and ownership: NFT-backed shares, a program-owned vote account, two-phase reward
rebalancing across epoch boundaries, and NFT-weighted on-chain governance. Devnet-only, 2023.

The two repositories cover the two halves of the same problem. That one is the protocol-level work
— vote account state, stake delegation, PDA-owned authorities. This one is the operational work —
actually running the node, and the networking, storage and observability that takes.

Joining them up is a recorded stretch goal: see
[phase two](docs/phase-two-ingl-integration.md) for pointing this platform at a vote account the
Ingl program creates, what would change, and the Alpenglow blocker that may already have closed the
window.

## Prior art

- [`dysnix/charts`](https://github.com/dysnix/charts) — the only maintained Solana Helm chart.
  This chart differs in: node-layer tuning via cloud-init rather than a privileged initContainer,
  testnet-sized values rather than mainnet defaults (2Ti PVCs), and a slot-diff readiness probe
  rather than `getHealth`.
- [`asymmetric-research/solana-exporter`](https://github.com/asymmetric-research/solana-exporter) —
  note that `certusone/solana_exporter` *redirects* here; it is the transferred Certus One
  exporter, not a fork.

## License

MIT
