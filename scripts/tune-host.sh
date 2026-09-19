#!/usr/bin/env bash
# Apply Anza's network sysctls to THIS HOST, for running a validator under kind/k3d.
#
# WHY THIS EXISTS: on a cloud node these are applied by node-pool cloud-init
# (terraform/modules/oci-oke/cloud-init/worker-init.sh). kind has no such hook — its "node" is a
# container, and net.core.* are NOT network-namespaced, so the kind node reads the HOST's values
# and the only way to change them is to change the host's.
#
# Without them agave-validator refuses to start:
#   net.core.rmem_max: recommended=134217728, current=4194304 too small
#   Validator command failed: OS network limit test failed.
#
# These are standard, benign values: larger socket buffers. They are what every Solana validator
# runs with. Nothing here is Solana-specific beyond the size.
#
#   ./scripts/tune-host.sh            # show what would change
#   sudo ./scripts/tune-host.sh -w    # apply, until reboot
#   sudo ./scripts/tune-host.sh -p    # apply AND persist via /etc/sysctl.d
set -euo pipefail

declare -A WANT=(
  [net.core.rmem_max]=134217728
  [net.core.rmem_default]=134217728
  [net.core.wmem_max]=134217728
  [net.core.wmem_default]=134217728
  [vm.max_map_count]=1000000
)

MODE="${1:---show}"

printf '%-26s %-14s %-14s %s\n' KEY CURRENT WANTED STATUS
for k in "${!WANT[@]}"; do
  cur="$(sysctl -n "$k" 2>/dev/null || echo '?')"
  want="${WANT[$k]}"
  if [[ "$cur" == "?" ]]; then st="absent"
  elif (( cur >= want )); then st="ok"
  else st="TOO SMALL"; fi
  printf '%-26s %-14s %-14s %s\n' "$k" "$cur" "$want" "$st"
done

case "$MODE" in
  --show|-s)
    echo
    echo "Nothing changed. Apply with:  sudo $0 -w     (or -p to persist)"
    ;;
  -w|-p)
    [[ $EUID -eq 0 ]] || { echo; echo "Needs root."; exit 1; }
    echo
    for k in "${!WANT[@]}"; do sysctl -w "$k=${WANT[$k]}"; done
    if [[ "$MODE" == "-p" ]]; then
      f=/etc/sysctl.d/21-agave-validator.conf
      : > "$f"
      for k in "${!WANT[@]}"; do echo "$k = ${WANT[$k]}" >> "$f"; done
      echo "persisted to $f"
    else
      echo
      echo "Applied until reboot. To revert now:"
      echo "  sudo sysctl -w net.core.rmem_max=4194304 net.core.wmem_max=4194304 net.core.rmem_default=212992 net.core.wmem_default=212992"
    fi
    ;;
  *) echo "usage: $0 [--show|-w|-p]"; exit 64 ;;
esac
