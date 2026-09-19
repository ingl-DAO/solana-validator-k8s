# Local testnet follower — measured results

A real Agave 4.2.2 node synced to Solana testnet, running on kind on a 12-core / 14 GB laptop
behind NAT. 2026-09-19.

## Proof it worked

```
$ kubectl get pod solana-solana-node-0
NAME                   READY   STATUS    RESTARTS   AGE
solana-solana-node-0   2/2     Running   0          6m16s

getHealth   -> "ok"
getVersion  -> {"feature-set":565236538,"solana-core":"4.2.2"}
getSlot     -> 442209465
lag         -> 33 slots (threshold 150)
```

Prometheus, end to end — the chain most likely to fail silently:

```
pool:      serviceMonitor/default/solana-solana-node/0
health:    UP
app=       solana                      <- relabeling applied
hostname=  solana-dev-control-plane    <- relabeling applied
lastError: (none)

solana_node_slot_height   442209566
solana_node_is_healthy    1
solana_node_num_slots_behind  0
```

## Numbers nobody publishes

### Memory: peak 6.69 GiB

| Phase | Memory |
|---|---|
| Snapshot download | ~1.2 GiB |
| **Accounts index generation** | **6.69 GiB (peak)** |
| Bank loading | ~3.4 GiB |
| Steady state, synced | ~5.5–6.5 GiB |

With `--accounts-index-limit minimal` on testnet. Request was 5 GiB, limit 9 GiB; the limit was a
guess and happened to be right, with ~2.3 GiB of headroom.

**The peak is a startup transient, not the steady state.** Sizing on observed steady-state memory
would undersize the pod and OOM it on the next restart — a workload that runs until it reboots.

For scale: Anza's mainnet guidance is 256 GB. A testnet follower needs roughly **1/40th** of that.

### Disk: 53 GB after one hour

```
accounts    33 GB     <- dominant, and not what the plan assumed
ledger      15 GB     <- grows toward --limit-ledger-size
snapshots    5 GB
```

The plan modelled 250 GB ledger + 100 GB accounts from estimates. Measured: accounts dominates
early and the split is nothing like the guess.

### Time to sync

Snapshot download to `Ready`: roughly 45 minutes, most of it the 5.3 GB fetch at 6.4 MB/s and the
index build across 94,724 slots.

## What this configuration does NOT prove

- **Gossip reachability.** Behind NAT, nothing can dial in. The node advertises an address it
  cannot serve.
- **Cloud IaC.** The OCI layer is written and validated but was never applied — see
  [ADR 0012](../../decisions/0012-trial-cannot-launch-paid-compute.md).
- **Voting.** Non-voting follower; no stake, no vote account, no delinquency risk.
