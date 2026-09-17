# 4. Build Agave from Source

## Status
Accepted

## Context
The agave-validator binary must be available in the container image. Options include pulling pre-built binaries or compiling from source.

## Decision
Build the agave-validator binary from source using `cargo install agave-validator --version 4.2.2 --locked`.

## Consequences
**Follows upstream reality.** The official Agave release tarball has not shipped agave-validator since version 3.0. Anza's v3.0.2+ release notes explicitly state this. Verified by inspecting release tarball contents: v2.1.21 (100 entries), v2.3.11 (40), v3.0.8, v4.2.2 (17 entries, no binary).

**Reproducible builds.** `--locked` uses the exact dependency lock file from the release tag, preventing dependency drift.

**Source of truth.** The official release source is the only authoritative build.

**Trade-off: longer build time.** Compiling Agave from source takes ~15 minutes on the container build system. Pre-built images exist but may not match the exact version needed.

**Fallback option available.** `ghcr.io/dysnix/docker-agave:v4.2.2` provides a pre-built alternative if source builds become infeasible. Note that `scripts/cargo-install-all.sh --validator-only` is deprecated in 4.2.2 and is not actually validator-only.
