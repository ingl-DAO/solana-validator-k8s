# Shared OCI session handling. Source this; do not execute it.
#
# Solves three things that bite repeatedly:
#   1. `oci session authenticate` writes whatever profile name you type, so the working session is
#      often NOT [DEFAULT]. Profile lookup is case-sensitive, and the CLI's own error messages
#      normalise case, so "already exists" and "not found" can both be true of the same name.
#   2. An expired token makes the CLI BLOCK rather than error.
#   3. Session-token auth is not used unless OCI_CLI_AUTH=security_token is set.

CONFIG="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"

# cfg <key> [profile] — read a key from a profile section. No API call, no auth.
cfg() {
  local k="$1" p="${2:-$OCI_PROFILE}"
  awk -v p="[$p]" -v k="$k" '
    $0==p {inp=1; next}
    /^\[/ {inp=0}
    inp && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
    }' "$CONFIG"
}

# Every call gets a timeout: an expired token hangs instead of failing.
oci_t() { timeout "${OCI_TIMEOUT:-30}" oci "$@"; }

_profiles() { grep -oP '^\[\K[^\]]+' "$CONFIG" 2>/dev/null; }

_probe() {
  local p="$1" tenancy
  tenancy="$(cfg tenancy "$p")"
  [[ -n "$tenancy" ]] || return 1
  local extra=()
  [[ -n "$(cfg security_token_file "$p")" ]] && extra=(--auth security_token)
  timeout 25 oci iam region-subscription list --tenancy-id "$tenancy" \
    --profile "$p" "${extra[@]}" >/dev/null 2>&1
}

# Pick a profile whose session actually works. Honours OCI_CLI_PROFILE if set, otherwise tries
# profiles newest-token-first, because that is almost always the one just authenticated.
oci_select_profile() {
  [[ -f "$CONFIG" ]] || { echo "No $CONFIG. Run: oci session authenticate" >&2; return 1; }

  local candidates=()
  if [[ -n "${OCI_CLI_PROFILE:-}" ]]; then
    candidates=("$OCI_CLI_PROFILE")
  else
    # newest token first, then any profile without a token (api-key auth)
    while read -r _ p; do candidates+=("$p"); done < <(
      for p in $(_profiles); do
        local tf; tf="$(cfg security_token_file "$p")"
        if [[ -n "$tf" && -f "$tf" ]]; then
          echo "$(stat -c %Y "$tf") $p"
        else
          echo "0 $p"
        fi
      done | sort -rn
    )
  fi

  local p
  for p in "${candidates[@]}"; do
    if _probe "$p"; then
      export OCI_PROFILE="$p"
      export OCI_CLI_PROFILE="$p"
      [[ -n "$(cfg security_token_file "$p")" ]] && export OCI_CLI_AUTH=security_token
      OCI_TENANCY="$(cfg tenancy "$p")"
      OCI_REGION_NAME="$(cfg region "$p")"
      export OCI_TENANCY OCI_REGION_NAME
      echo "profile: [$p]  region: $OCI_REGION_NAME  auth: ${OCI_CLI_AUTH:-api_key}"
      return 0
    fi
    echo "  [$p] session not usable, trying next" >&2
  done

  cat >&2 <<EOF

No profile in $CONFIG has a working session. Profiles found: $(_profiles | tr '\n' ' ')

Profile names are CASE-SENSITIVE and 'oci session authenticate' writes whichever name you type,
so the live session is often not [DEFAULT].

  oci session authenticate          # then note the profile name it reports
  OCI_CLI_PROFILE=<that-name> $0

EOF
  return 1
}
