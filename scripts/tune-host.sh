#!/usr/bin/env bash
# Host sysctls required to run agave-validator under kind/k3d.
#
# SCOPE: only the four settings agave-validator actually checks. Extracted from the binary:
#   grep -aoE '(net\.core\.[a-z_]+){2,}' agave-validator
#     -> net.core.rmem_max, net.core.wmem_max, net.core.optmem_max, net.core.netdev_max_backlog
#
# All four are *_max / backlog CEILINGS. Raising a ceiling allocates nothing: it only permits an
# application that explicitly asks (setsockopt SO_RCVBUF/SO_SNDBUF) to get a larger buffer.
# Processes that do not ask are unaffected.
#
# Deliberately NOT set: net.core.rmem_default and net.core.wmem_default. Anza's own tuning guide
# lists them and the cloud node-pool init applies them, but agave-validator does not check them,
# and unlike the ceilings they change the default for EVERY socket on the machine. On a laptop
# that is a real behavioural change for no benefit, so it is skipped here. The cloud profile,
# where the node does nothing else, still sets them.
#
# WHY THIS IS NEEDED AT ALL: net.core.* are not network-namespaced, so a kind "node" - being a
# container - reads the host's values. A real node pool applies these via cloud-init
# (terraform/modules/oci-oke/cloud-init/worker-init.sh); kind has no such hook, and agave has no
# flag to skip the check.
#
#   ./scripts/tune-host.sh          # show only
#   sudo ./scripts/tune-host.sh -w  # apply until reboot
#   sudo ./scripts/tune-host.sh -p  # apply and persist
set -euo pipefail

KEYS=(net.core.rmem_max net.core.wmem_max net.core.optmem_max net.core.netdev_max_backlog)
declare -A WANT=(
  [net.core.rmem_max]=134217728
  [net.core.wmem_max]=134217728
  [net.core.optmem_max]=131072
  [net.core.netdev_max_backlog]=30000
)

MODE="${1:---show}"
NEED=()

printf '%-30s %-12s %-12s %s\n' KEY CURRENT NEEDED STATUS
for k in "${KEYS[@]}"; do
  cur="$(sysctl -n "$k" 2>/dev/null || echo '')"
  want="${WANT[$k]}"
  if [[ -z "$cur" ]]; then
    printf '%-30s %-12s %-12s %s\n' "$k" "absent" "$want" "skip"
  elif (( cur >= want )); then
    printf '%-30s %-12s %-12s %s\n' "$k" "$cur" "$want" "ok"
  else
    printf '%-30s %-12s %-12s %s\n' "$k" "$cur" "$want" "RAISE"
    NEED+=("$k")
  fi
done

if [[ ${#NEED[@]} -eq 0 ]]; then
  echo; echo "Nothing to change."; exit 0
fi

case "$MODE" in
  --show|-s)
    echo
    echo "Would raise: ${NEED[*]}"
    echo "These are ceilings — raising them allocates no memory and changes no running process."
    echo
    echo "  sudo $0 -w     apply until reboot"
    echo "  sudo $0 -p     apply and persist"
    ;;
  -w|-p)
    [[ $EUID -eq 0 ]] || { echo; echo "Needs root."; exit 1; }
    echo
    # Record the originals so the revert line below is exact.
    revert=""
    for k in "${NEED[@]}"; do
      revert+=" $k=$(sysctl -n "$k")"
      sysctl -w "$k=${WANT[$k]}"
    done
    if [[ "$MODE" == "-p" ]]; then
      f=/etc/sysctl.d/21-agave-validator.conf
      : > "$f"
      for k in "${NEED[@]}"; do echo "$k = ${WANT[$k]}" >> "$f"; done
      echo "persisted to $f  (delete the file to undo)"
    fi
    echo
    echo "Revert with:"
    echo "  sudo sysctl -w$revert"
    ;;
  *) echo "usage: $0 [--show|-w|-p]"; exit 64 ;;
esac
