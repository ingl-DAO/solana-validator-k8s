#!/usr/bin/env bash
# Create the OCI Object Storage bucket that holds Terraform state, and the S3-compatible
# credentials the backend needs.
#
# Terraform has no native OCI state backend. OCI Object Storage speaks an S3-compatible API, so
# the standard `backend "s3"` works — with a pile of skip_* flags to stop it assuming AWS.
#
# Run once. Idempotent: re-running will not duplicate the bucket, and will not mint a second
# credential unless you pass --new-key.
#
#   oci session authenticate
#   ./scripts/bootstrap-state.sh
#
# WHAT THIS CREATES
#   1. A versioned Object Storage bucket.
#   2. A Customer Secret Key on your user — an ACCESS KEY / SECRET PAIR. OCI shows the secret
#      exactly once, at creation. It is written to terraform/.s3-credentials (0600, gitignored).
#      Treat it as a password. You may hold at most 2 per user.
set -euo pipefail

NEW_KEY=0
[[ "${1:-}" == "--new-key" ]] && NEW_KEY=1

command -v oci >/dev/null || { echo "oci CLI not found. pipx install oci-cli"; exit 1; }
command -v jq  >/dev/null || { echo "jq not found"; exit 1; }

CONFIG="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"
PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"
cfg() {
  awk -v p="[$PROFILE]" -v k="$1" '
    $0==p {inp=1; next}
    /^\[/ {inp=0}
    inp && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
    }' "$CONFIG"
}

TENANCY="${OCI_TENANCY_OCID:-$(cfg tenancy)}"
REGION="${OCI_REGION:-$(cfg region)}"
TOKEN_FILE="$(cfg security_token_file)"
[[ -n "$TENANCY" && -n "$REGION" ]] || { echo "No tenancy/region in [$PROFILE] of $CONFIG. Run 'oci session authenticate'."; exit 1; }
[[ -n "$TOKEN_FILE" ]] && export OCI_CLI_AUTH=security_token
export OCI_CLI_PROFILE="$PROFILE"

# Fail fast on an expired session. `oci session authenticate` tokens last about an hour, and an
# expired one makes the CLI BLOCK rather than error — it sits there waiting on a re-auth that
# never comes. Every call below is wrapped in a timeout for the same reason.
oci_t() { timeout 30 oci "$@"; }

if ! oci_t iam region-subscription list --tenancy-id "$TENANCY" >/dev/null 2>&1; then
  echo "The session token is expired or not working (the CLI hangs rather than failing on this)."
  echo "Refresh it and re-run:"
  echo "  oci session refresh --profile $PROFILE"
  echo "or, if that fails:"
  echo "  oci session authenticate"
  exit 1
fi

BUCKET="${STATE_BUCKET:-tfstate-solana-validator-k8s}"
OUT_DIR="terraform"
CRED_FILE="$OUT_DIR/.s3-credentials"
BACKEND_FILE="$OUT_DIR/envs/oci-testnet/backend.hcl"

echo "tenancy: $TENANCY"
echo "region:  $REGION"
echo "bucket:  $BUCKET"
echo

# --- 1. namespace -------------------------------------------------------------------------------
NS="$(oci_t os ns get --query 'data' --raw-output)"
[[ -n "$NS" ]] || { echo "Could not read the Object Storage namespace."; exit 1; }
echo "namespace: $NS"

# --- 2. bucket ----------------------------------------------------------------------------------
if oci_t os bucket get --bucket-name "$BUCKET" >/dev/null 2>&1; then
  echo "bucket exists, leaving it alone"
else
  echo "creating bucket..."
  oci_t os bucket create \
    --compartment-id "$TENANCY" \
    --name "$BUCKET" \
    --versioning Enabled \
    --public-access-type NoPublicAccess \
    >/dev/null
  echo "created (versioning enabled — state history survives a bad apply)"
fi

# --- 3. S3-compatible credentials ---------------------------------------------------------------
# Needs the user OCID. Session tokens do not put it in the config file, so decode it out of the
# JWT's `sub` claim. Override with OCI_USER_OCID if this ever stops working.
get_user_ocid() {
  if [[ -n "${OCI_USER_OCID:-}" ]]; then echo "$OCI_USER_OCID"; return; fi
  local u; u="$(cfg user)"
  if [[ -n "$u" ]]; then echo "$u"; return; fi
  if [[ -n "$TOKEN_FILE" && -f "$TOKEN_FILE" ]]; then
    python3 - "$TOKEN_FILE" <<'PY'
import base64, json, sys
tok = open(sys.argv[1]).read().strip().split('.')
if len(tok) >= 2:
    pad = tok[1] + '=' * (-len(tok[1]) % 4)
    claims = json.loads(base64.urlsafe_b64decode(pad))
    for k in ('sub', 'user_ocid', 'principal'):
        v = claims.get(k, '')
        if isinstance(v, str) and v.startswith('ocid1.user'):
            print(v); break
PY
  fi
}

USER_OCID="$(get_user_ocid)"
if [[ -z "$USER_OCID" ]]; then
  echo
  echo "Could not determine your user OCID automatically."
  echo "Find it in Console -> Profile -> User settings, then re-run:"
  echo "  OCI_USER_OCID=ocid1.user.oc1..xxx $0"
  exit 1
fi
echo "user: $USER_OCID"

EXISTING="$(oci_t iam customer-secret-key list --user-id "$USER_OCID" 2>/dev/null \
            | jq -r '[.data[] | select(."lifecycle-state"=="ACTIVE")] | length')"
EXISTING="${EXISTING:-0}"

if [[ -f "$CRED_FILE" && $NEW_KEY -eq 0 ]]; then
  echo "credentials already at $CRED_FILE (pass --new-key to mint another)"
elif [[ "$EXISTING" -ge 2 && $NEW_KEY -eq 0 ]]; then
  echo "You already hold 2 customer secret keys (the maximum) and $CRED_FILE is missing."
  echo "OCI only reveals a secret at creation, so an existing one cannot be recovered."
  echo "Delete one in Console -> Profile -> Customer secret keys, then re-run."
  exit 1
else
  echo "minting an S3-compatible credential..."
  RESP="$(oci_t iam customer-secret-key create \
            --user-id "$USER_OCID" \
            --display-name "terraform-state-$BUCKET")"
  AK="$(echo "$RESP" | jq -r '.data.id')"
  SK="$(echo "$RESP" | jq -r '.data.key')"
  [[ -n "$AK" && -n "$SK" && "$SK" != "null" ]] || { echo "Key creation returned no secret."; exit 1; }
  mkdir -p "$OUT_DIR"
  umask 077
  cat > "$CRED_FILE" <<EOF
# S3-compatible credentials for the Terraform state backend. SECRET — never commit.
# OCI reveals the secret only at creation; if you lose this file, delete the key and re-run.
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
EOF
  chmod 600 "$CRED_FILE"
  echo "written to $CRED_FILE (0600)"
fi

# --- 4. backend config --------------------------------------------------------------------------
mkdir -p "$(dirname "$BACKEND_FILE")"
cat > "$BACKEND_FILE" <<EOF
# Generated by scripts/bootstrap-state.sh — safe to commit, contains no secrets.
# Credentials come from terraform/.s3-credentials via the environment.
bucket = "$BUCKET"
key    = "oci-testnet/terraform.tfstate"
region = "$REGION"

endpoints = {
  s3 = "https://$NS.compat.objectstorage.$REGION.oraclecloud.com"
}

use_path_style = true

# OCI is not AWS. Without these the backend tries to validate the region, call STS, and read the
# EC2 metadata service, all of which fail.
skip_region_validation      = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true

# Required. OCI's S3 API rejects the newer AWS checksum headers, and the failure is an opaque
# 400 rather than anything that names checksums.
skip_s3_checksum = true
EOF
echo "backend config: $BACKEND_FILE"

cat <<EOF

Next:

  source terraform/.s3-credentials
  cd terraform/envs/oci-testnet
  terraform init -backend-config=../../../$BACKEND_FILE

Migrating existing local state? Terraform will offer to copy it — answer yes.

NOTE ON LOCKING: the S3 backend locks via DynamoDB, which OCI has no equivalent for, so this
backend is UNLOCKED. Fine for one operator; it would not be for a team. Recorded in
docs/decisions/0011-remote-state-on-oci-object-storage.md.

TEARDOWN: the bucket dies with the trial. scripts/down.sh empties it and commits the proof; the
state itself is never committed.
EOF
