# 11. Remote State on OCI Object Storage

## Status
Accepted

## Context
Terraform state must be stored and shared across deployments. Local state is convenient but breaks in team environments and CI pipelines.

## Decision
Store Terraform state in an OCI Object Storage bucket via the S3-compatible backend. Bootstrap the bucket with `scripts/bootstrap-state.sh`. Never commit state to the repository.

## Consequences
**Bucket is ephemeral.** Because the OCI trial account terminates and state is created within it, the bucket dies with the trial. State is not backed up to a persistent service.

**Prove, don't keep.** Instead of committing state itself, the repo commits the proof that the bucket existed and was emptied. This is the teardown assertion output from the bootstrap script. It serves as audit evidence without storing sensitive state.

**State is remote and shared.** The S3-compatible backend allows multiple deployments and CI pipelines to read and update state safely. Concurrent access is serialized.

**Backend is transparent.** HCL references resources naturally; the backend details are hidden in the Terraform configuration.

**Scripts automate setup.** `bootstrap-state.sh` handles bucket creation and backend configuration, reducing manual work and operator error.

**No state in version control.** State is never committed, preventing accidental exposure of sensitive data (database passwords, private IPs) in git history.

**Documented fallback.** If Object Storage becomes unavailable, local state (`terraform.tfstate`) remains available for emergency access.
