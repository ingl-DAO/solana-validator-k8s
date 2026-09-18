# syntax=docker/dockerfile:1.7
#
# linux/amd64 ONLY. No linux/aarch64 Agave binary has ever been published for any version, and
# Anza requires AVX2 + SHA extensions. See docs/decisions/0004-build-agave-from-source.md
#
# Stage A takes the tools that ARE shipped in the official tarball.
# Stage B builds agave-validator, which is NOT — it has not shipped in the release tarball since
# Agave 3.0 (Anza's own v3.0.2+ release notes say so). Verified by listing tarball contents:
#   v2.1.21 = 100 entries, v2.3.11 = 40, v3.0.8, v4.2.2 = 17 — and no agave-validator in the last.

ARG AGAVE_VERSION=4.2.2

# ---------- Stage A: official release tarball (CLI + ledger tool) ----------
FROM debian:trixie-slim AS tools
ARG AGAVE_VERSION
# Pin the checksum. Fill from: curl -sL <url> | sha256sum
ARG TARBALL_SHA256=5fc8684f7430038105fde953d4308ed56addf627f658daa61709f345448247ee
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates bzip2 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /tmp/r.tar.bz2 \
      "https://release.anza.xyz/v${AGAVE_VERSION}/solana-release-x86_64-unknown-linux-gnu.tar.bz2" \
 && if [ "$TARBALL_SHA256" != "REPLACE_ME" ]; then \
      echo "${TARBALL_SHA256}  /tmp/r.tar.bz2" | sha256sum -c -; \
    else echo "WARNING: building without checksum verification"; fi \
 && tar -xjf /tmp/r.tar.bz2 -C /tmp

# ---------- Stage B: build the validator ----------
# 1.96.1 is not a guess: it is what anza-xyz/agave pins in rust-toolchain.toml at tag v4.2.2.
# `cargo install` from crates.io does NOT read that file, so the toolchain has to be pinned here.
# Building 4.2.2 on 1.93.1 fails ~18 minutes in with seven E0133 errors in solana-core:
#   error[E0133]: call to unsafe function `__cpuid` is unsafe and requires unsafe function or block
# Always take the toolchain from the tag you are building:
#   curl -sL https://raw.githubusercontent.com/anza-xyz/agave/v<VERSION>/rust-toolchain.toml
FROM rust:1.98.0-slim-trixie AS build
ARG AGAVE_VERSION
# Cap build parallelism. Linking rocksdb peaks at roughly 2 GB per job, so on a 14 GB machine
# an unbounded `-j$(nproc)` on 12 cores OOMs partway through — after 40 minutes of work.
ARG CARGO_JOBS=6
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config libudev-dev llvm libclang-dev \
      protobuf-compiler libssl-dev cmake git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# crates.io publishes agave-validator and it is not yanked — shortest reproducible path.
#
# The Anza-blessed alternative is:
#   ./scripts/cargo-install-all.sh --no-build-dev-bins --no-build-deprecated-bins \
#       --no-build-platform-tools --no-build-dcou-bins --no-spl-token <dir>
# Note that --validator-only is DEPRECATED in 4.2.2 and is NOT actually validator-only: it still
# builds every end-user and DCOU binary. That is the kind of thing you only learn by running it.
#
# Expect 30-60 min and a 30-50 GB target dir. Do not build this on a GitHub-hosted runner
# (~14 GB free disk) — it dies partway through linking.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install agave-validator --version ${AGAVE_VERSION} --locked --root /out -j ${CARGO_JOBS}

# ---------- Runtime ----------
FROM debian:trixie-slim
ARG AGAVE_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl jq bzip2 zstd libssl3 bash \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -u 10001 -m -s /usr/sbin/nologin solana

COPY --from=build /out/bin/agave-validator /usr/local/bin/
COPY --from=tools /tmp/solana-release/bin/solana \
                  /tmp/solana-release/bin/solana-keygen \
                  /tmp/solana-release/bin/solana-test-validator \
                  /tmp/solana-release/bin/agave-ledger-tool /usr/local/bin/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER 10001
WORKDIR /data
LABEL org.opencontainers.image.version="${AGAVE_VERSION}" \
      org.opencontainers.image.source="https://github.com/marcjazz/solana-validator-k8s" \
      org.opencontainers.image.licenses="MIT"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
