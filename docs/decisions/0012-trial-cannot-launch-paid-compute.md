# 12. The OCI free trial cannot launch paid compute

## Status

Accepted, 2026-09-19. Discovered at `terraform apply`, not from documentation.

## Context

The plan assumed the €250 of free-trial credits could be spent on paid compute shapes. Oracle's
own documentation encourages that reading: credits exist, paid shapes are listed, service limits
are non-zero. Ours showed **13 OCPU / 208 GB available** for `VM.Standard.E5.Flex`.

The node pool created successfully and then failed to launch its single node:

```
400, LimitExceeded: Your resource creation limit has been reached. To unblock resource
creation, please upgrade to a Pay As You Go or Oracle Universal Credits account, or delete
resources to restore your resource creation capability.
```

This is **not** a service limit. Service limits were verified non-zero and sufficient. It is a
separate, account-level restriction: a Free Trial tenancy may create **Always Free** resources
only, whatever the credit balance says. Credits become spendable when the account is upgraded.

The distinction matters because the two produce nearly identical-looking failures and the fix for
one does nothing for the other:

| | Service limit | Trial resource-creation limit |
|---|---|---|
| Check with | `oci limits value list` | not exposed by any API |
| Error | `LimitExceeded` at launch | `LimitExceeded` at launch |
| Fix | request an increase | upgrade the account |
| Visible before trying | yes | **no** |

Neither the console, nor `oci limits`, nor the budget page indicates the second exists. The only
way to find it is to attempt a launch.

The Always Free shapes cannot substitute here:

- `VM.Standard.A1.Flex` — ARM. No `linux/aarch64` Agave binary has ever been published, and Anza
  requires AVX2 + SHA extensions ([ADR 0004](0004-build-agave-from-source.md)).
- `VM.Standard.E2.1.Micro` — 1 GB RAM.

## Decision

**Upgrade the tenancy to Pay As You Go.**

The alternatives were rejected:

- *Always Free only* — no shape can run the workload, for architecture and memory reasons that no
  amount of tuning changes.
- *Another provider* — viable (a capable x86 box is roughly €15–30/month), but it discards the OCI
  work and the OKE integration that is a substantial part of what this project demonstrates.
- *Stop at tier 1* — `make dev-up` on kind already works with no cloud at all, so the repository
  survives. It loses the claim of having actually run a syncing node, which is the point.

## Consequences

- The €250 of credits is consumed **before** any charge, so the modelled ~$30 build should cost
  nothing in real money.
- After credits are exhausted or expire, billing is genuine. The budget guardrail from
  [ADR 0002](0002-oke-basic-vs-k3s-vm.md) stops being a tidiness measure: the forecast alert at
  80% is the thing standing between a forgotten `make pause` and a real invoice.
- Always Free resources stay free after the upgrade.
- Nothing created so far bills. OKE Basic control plane, VCN, subnets, NSGs and gateways are all
  $0; no compute or block volume was ever launched. Spend at the time of this decision: **€0.00**.

## The transferable lesson

Non-zero service limits do not imply you can create the resource. On a trial tenancy they describe
what the account *would* be allowed if it could create anything at all. The only reliable test is
to launch one instance of the smallest paid shape and see what happens — a five-minute check that
would have saved this discovery until after a cluster had been built around the assumption.
