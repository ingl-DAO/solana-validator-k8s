#!/usr/bin/env bash
# Create the node's identity keypair Secret, once.
#
# The identity is the node's STABLE gossip identity. Regenerating it on every deploy would make
# the node look like a new participant each time, so this is idempotent by design.
#
# A follower does not vote, so this key signs nothing of value — but it must not change.
set -euo pipefail

RELEASE="${RELEASE:-solana}"
SECRET="${RELEASE}-solana-node-identity"
IMAGE="${IMAGE:-ghcr.io/marcjazz/agave:4.2.2}"

if kubectl get secret "$SECRET" >/dev/null 2>&1; then
  echo "identity secret $SECRET already exists, keeping it"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --user is required. The image runs as uid 10001 (non-root, deliberately), so without this the
# container cannot write to a bind mount owned by the host user and fails with
#   Unable to write /out/identity.json: Permission denied (os error 13)
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$tmp:/out" \
  --entrypoint solana-keygen \
  "$IMAGE" new --no-bip39-passphrase -s -o /out/identity.json >/dev/null

[[ -s "$tmp/identity.json" ]] || { echo "keygen produced no file"; exit 1; }

kubectl create secret generic "$SECRET" --from-file=identity.json="$tmp/identity.json"

pubkey="$(docker run --rm --user "$(id -u):$(id -g)" -v "$tmp:/out" \
  --entrypoint solana-keygen "$IMAGE" pubkey /out/identity.json 2>/dev/null || true)"
[[ -n "$pubkey" ]] && echo "identity: $pubkey"
