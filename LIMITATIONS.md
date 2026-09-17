# Limitations

Written before the build, not after, so it cannot be accused of being retrofitted.

## This runs on an unsupported path, deliberately

Anza states verbatim that running an Agave validator for live clusters inside Docker "is not
recommended and generally not supported", and that cloud operation "requires significantly greater
operational expertise to achieve stability and performance". Anza's own Kubernetes project,
`anza-xyz/validator-lab`, was **archived on 2026-02-23**. Helius, Triton and Blockdaemon all run
bare metal.

This project exercises that unsupported path anyway, with the mitigations enumerated in the ADRs.
That framing is the point: a repo implying you would put a mainnet validator on managed Kubernetes
would be worse than one that says plainly where the path stops being supported and why it was
still worth walking.

## The blockstore floor is large, but it fits

`--limit-ledger-size` has a **minimum** of 50,000,000 shreds on Agave 4.2.x. You cannot configure
a smaller blockstore. At ~1250 B/shred that is ~62 GB of data shreds and, once coding shreds are
counted, potentially ~125 GB on disk. It is a FIFO ceiling rather than a preallocation, and testnet
in practice sits far below it.

An earlier draft of this file recorded that this floor exceeded the available storage quota. That
was wrong, and the way it was wrong is worth keeping: it was computed against
`total-free-storage-gb` (200 GB, the Always Free allowance) rather than `total-storage-gb`
(30,720 GB per AD, the actual limit on a credit-funded trial). The ledger volume is now 250 GB,
which clears the worst case with room to spare, and `SolanaLedgerDiskFilling` is a genuine alert
rather than a compensating control for an undersized disk.

## Storage is generous; the shape is the constraint

Accounts and ledger are on **separate volumes**, as Anza recommends — 100 GB and 250 GB. The
binding constraint in this tenancy turned out to be compute, not storage:
`standard-e4-core-count` is 0 (E4 unavailable entirely) and E5 allows 13 OCPU / 208 GB per AD, of
which this uses 8 / 96 to stay inside the credit balance. See ADR 0010.

## Still one node

`replicas: 1` for the reasons below, not for storage ones — that rationale did not survive
measurement (ADR 0007).

## Single node, single replica

`replicas: 1` is not a scaling limitation to be fixed later — it is correct. Two pods sharing an
identity keypair double-sign. Solana HA is gossip-based identity failover, which Kubernetes'
surge-before-terminate semantics actively fight. `updateStrategy: OnDelete` is set for the same
reason.

## Non-voting

No vote account, no stake, no rewards, no delinquency risk, and therefore none of the economics
that make validator operations hard. Testnet is also mid-Alpenglow (mainnet activation targeted
2026-09-28), which adds a BLS pubkey in the vote account and a ~1.6 SOL/epoch burned Validator
Admission Ticket — a moving target inside a 22-day window.

## The readiness probe is a proxy

`getHealth` is unusable as an HTTP probe: it returns **HTTP 200** carrying a JSON-RPC error body
(`-32005 NodeUnhealthy`), so an `httpGet` probe passes unconditionally. Under Alpenglow,
`RpcHealth::check()` also requires Votor to have observed a finalization certificate and returns
`Unknown` until then, which an unstaked node may never satisfy. The probe therefore compares
`getMaxShredInsertSlot` against `getSlot` — which measures shred ingestion, not consensus
participation. Good enough here; not equivalent to health.

## seccomp Unconfined

Agave ≥2.0 uses `io_uring` to unpack snapshots, and `RuntimeDefault` blocks
`io_uring_setup/enter/register`. Running `Unconfined` is a genuine weakening of the sandbox, and on
a cluster enforcing PodSecurity `restricted` there is no workaround short of a policy exemption.

## `--no-port-check`

A real startup check, disabled so a transiently-closed port does not abort a boot that costs a
snapshot fetch to retry. Documented rather than hidden.

## Operational knowledge does not port

The infra contract keeps the *chart* portable across clouds. It does not make the *debugging*
portable. The UDP diagnosis in `docs/runbook.md` is OCI-flavoured; on AWS you would fight security
groups and a different metadata endpoint instead.

## The evidence is a snapshot

The OCI trial expires. Everything in `docs/evidence/` is a record of a system that no longer runs.
The only permanently executable part of this repo is `make dev-up`.
