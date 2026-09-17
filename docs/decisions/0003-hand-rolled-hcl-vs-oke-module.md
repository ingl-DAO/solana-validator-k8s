# 3. Hand-Rolled HCL vs OKE Module

## Status
Accepted

## Context
OCI publishes oracle-terraform-modules/oke, a Terraform module encapsulating the OKE provisioning pattern. The alternative is writing raw HCL.

## Decision
Write raw HCL (~400 lines) rather than invoke the module.

## Consequences
**Readability for code review.** Raw HCL can be read linearly from top to bottom. The reviewer sees every NSG rule, node pool shape, and cloud-init setting directly. A module invocation hides these critical details behind variable defaults.

**Minimal added maintenance.** 400 lines of well-structured HCL is not significantly harder to maintain than a module invocation that requires reading the module's source to understand actual behavior.

**Clear intent.** When someone reviews the Terraform, they see exactly what is being provisioned, not what the module's defaults assume.

**Reference available.** The equivalent module approach is documented in `terraform/modules/oci-oke/ALTERNATIVE.md` as ~50 lines, enabling future migration if needed.

**Trade-off: no free updates.** Module updates might include optimizations or fixes. Raw HCL requires manual review and application of changes.
