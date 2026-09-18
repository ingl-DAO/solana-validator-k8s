# Official Agave release tarball contents

Captured 2026-09-18 from:
  https://release.anza.xyz/v4.2.2/solana-release-x86_64-unknown-linux-gnu.tar.bz2

    size    86,382,236 bytes
    sha256  5fc8684f7430038105fde953d4308ed56addf627f658daa61709f345448247ee

## bin/

```
agave-install
agave-install-init
agave-ledger-tool
cargo-build-sbf
cargo-test-sbf
solana
solana-keygen
solana-stake-accounts
solana-test-validator
solana-tokens
spl-token
```

**12 binaries. `agave-validator` is not among them.**

This is the finding the whole image build rests on. Anza stopped shipping `agave-validator`
in the release tarball at Agave 3.0, so every tutorial that does
`curl release.anza.xyz/... | tar x && ./bin/agave-validator` is describing 2.3 or earlier.
The validator has to be built from source, or taken from a community image.

`solana-test-validator` **is** present, which is why the chart's `mode: test-validator`
works from the tarball alone and needs no compilation.


---

# Build record

Built 2026-09-18 on a 12-core / 14 GB laptop, Docker 29.8.1.

| | |
|---|---|
| cargo stage | **18.1 min** (`-j6`) |
| image size | **499 MB** |
| result | `agave-validator 4.2.2 (feat:21b0d33a, client:Agave)` |
| runs as | uid 10001, non-root |
| binaries | `agave-validator` (built), `solana`, `solana-keygen`, `solana-test-validator`, `agave-ledger-tool` (from the tarball) |

`feat:21b0d33a` matches the community image `ghcr.io/dysnix/docker-agave:v4.2.2` and the tarball
binaries exactly. The feature-set hash is what determines whether a node can join a cluster.

## The `src:` hash is not stable in this image — and that is a real cost

Three consecutive runs of the **same image digest**:

```
agave-validator 4.2.2 (src:a4d4f9dd; feat:21b0d33a, client:Agave)
agave-validator 4.2.2 (src:d5da2beb; feat:21b0d33a, client:Agave)
agave-validator 4.2.2 (src:ee6de554; feat:21b0d33a, client:Agave)
```

The community image, twice, for contrast:

```
agave-validator 4.2.2 (src:c9c6f328; feat:21b0d33a, client:Agave)
agave-validator 4.2.2 (src:c9c6f328; feat:21b0d33a, client:Agave)
```

`src:` is the **git commit the binary was built from**. `cargo install` pulls from crates.io,
where there is no git metadata, so the build script has nothing to bake in and the field degrades
to a value that differs on every invocation. An earlier draft of this file described it as merely
"a different hash" — it is not a different hash, it is **no hash at all**.

What that costs: the binary cannot state its own provenance. On a validator that matters, because
`src:` is how an operator confirms which commit is running when a cluster incident is traced to a
specific build. `feat:` — the field that governs whether the node can join at all — is correct and
stable, so this does not affect operation.

**The fix, if provenance is wanted:** build from a git checkout of the tag instead of from
crates.io. That also removes the toolchain trap below, because a checkout carries
`rust-toolchain.toml` and cargo honours it automatically. The cost is cloning the repository into
the build. Recorded rather than done — the running node is unaffected.

## The failure worth publishing

The first attempt died **18 minutes in**, on `rust:1.93.1`:

```
error[E0133]: call to unsafe function `__cpuid` is unsafe and requires unsafe function or block
error: could not compile `solana-core` (lib) due to 7 previous errors
```

`anza-xyz/agave` pins **1.96.1** in `rust-toolchain.toml` at tag `v4.2.2`. The trap is that
**`cargo install` from crates.io does not read `rust-toolchain.toml`** — building from a git
checkout picks the right toolchain up automatically, installing the published crate silently uses
whatever compiler the image happens to have, and the mismatch does not surface until deep inside
`solana-core` after 18 minutes of compilation.

For any other version:

```bash
curl -sL https://raw.githubusercontent.com/anza-xyz/agave/v<VERSION>/rust-toolchain.toml
```

## Resource notes

- `-j6` on 14 GB did **not** OOM. Linking rocksdb peaks around 2 GB per job, so an unbounded
  `-j$(nproc)` on 12 cores would have.
- Peak disk during the cargo stage was modest — about 5 GB of working space beyond the base images,
  well under the 30–50 GB commonly quoted. Docker released the failed build's cache on exit.
