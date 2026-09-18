# Phase two — run the validator Ingl creates

**Status:** not started. Recorded so the intent survives even if it is never built.

## The idea

This repository runs a generic Agave node. Phase two points the same platform at a vote account
created by [`ingl-DAO/permissionless-validators`](https://github.com/ingl-DAO/permissionless-validators) —
the on-chain program that fractionalizes validator ownership.

The pitch changes from *"I can run a Solana node on Kubernetes"* to *"I wrote part of the program
that creates a fractionalized validator, and here is the Kubernetes platform that operates the
validator it creates."* That is one project spanning protocol and infrastructure, rather than two
that happen to share an author.

## Why this is a delta, not a dependency

**The Kubernetes layer is identical.** An "Ingl validator" is an ordinary Solana validator whose
vote account happens to be owned by a program PDA rather than a human. Same StatefulSet, same
gossip ports, same storage profile, same probes, same exporter. Nothing in `charts/solana-node`
knows or cares who owns the vote account.

Everything that differs happens **on-chain, before the node starts**. So phase one is not wasted
work under any outcome — and if phase two proves infeasible, phase one is still a complete project.

## What actually changes

| | Phase one | Phase two |
|---|---|---|
| Cluster | testnet | **devnet** — that is where the Ingl program is deployed |
| Voting | `--no-voting` | **voting**, with `--vote-account <PDA>` |
| Identity | ephemeral | funded keypair, mounted as a Secret |
| Snapshot | 5.3 GB | **65.9 GB** — devnet is 12× larger |
| Chart | unchanged | `mode: follower` + `vote.enabled: true`, `vote.accountPubkey` |

Storage is affordable now that the real limit is known to be 30 TB per AD rather than 200 GB
(see [ADR 0007](decisions/0007-single-node-pool-storage-arithmetic.md)), but the initial sync is
materially longer and `--maximum-local-snapshot-age` stops being cheap — every scale-to-zero costs
a 65.9 GB refetch instead of 5.3 GB.

## The blockers, honestly

**1. Alpenglow may have already closed the window.** This is the decisive one. Under Alpenglow a
vote account needs a **BLS pubkey registered in it**, plus a ~1.6 SOL/epoch burned Validator
Admission Ticket. Devnet and testnet already run Alpenglow; mainnet activation was targeted
~2026-09-28. The Ingl program was written in 2023 and writes no BLS pubkey, so a vote account it
creates today may simply be unable to vote.

**Test this first, before anything else.** It is cheap and it is decisive.

**2. The program is pinned to Solana CLI v1.14.12** (March 2023). Current is 4.2.2. The deploy flow
(`cargo-x bda`, the `ingl` pip CLI) is 2023-era and will not work unmodified.

**3. `VoteState` handling is already a generation behind.** `state.rs` mirrors Solana's vote account
layout locally, and legacy `VoteStateVersions` support was deliberately removed. That mirror was
accurate in March 2023.

**4. Voting costs real SOL.** Devnet airdrops cover it, but the node must stay delinquency-free to
be worth showing, which turns a demo into an operational commitment.

## The order to attempt it

1. **Feasibility probe (1–2 h).** On devnet, with current tooling, create a vote account the way
   the program does and check whether the cluster accepts it as a voting participant under
   Alpenglow. If it does not, stop — write up the finding and link it from the Ingl README. *A
   documented "here is exactly why the 2023 program cannot vote on a 2026 cluster" is itself a
   strong artifact, and costs two hours instead of two weeks.*
2. **Revive the deploy path.** Get `cargo-x bda` and `ingl init` working against current Solana, or
   replace them with a minimal script that issues the same instructions.
3. **Create the instance.** `ingl init` → `ingl create_vote_account` → mint and delegate enough
   NFTs to back the stake.
4. **Point the chart at it.** Add `vote.enabled` / `vote.accountPubkey` to `values.yaml`, drop
   `--no-voting`, mount the identity keypair, switch `cluster: devnet`.
5. **Prove it.** `solana vote-account <pubkey> --url devnet` showing credits accruing, next to a
   Grafana panel showing the node's vote credits climbing. That screenshot is the entire point of
   phase two.

## When to abandon

Stop if step 1 fails, or if step 2 exceeds one evening. The economics of the Ingl model do not
close at any realistic scale (a new validator needs roughly 52,000 SOL of delegated stake to cover
vote costs), so this is a *demonstration* of joined-up protocol and infrastructure skill, not a
product revival. If it costs more than a weekend it is no longer buying what it was meant to buy.
