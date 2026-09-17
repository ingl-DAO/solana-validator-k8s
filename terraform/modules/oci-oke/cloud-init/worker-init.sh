#!/bin/bash
# OKE worker node bootstrap.
#
# ORDER MATTERS: the tuning runs BEFORE the OKE bootstrap block, so fs.nr_open is raised before
# containerd starts. Otherwise you are restarting containerd under a live kubelet.
#
# Oracle's rule is that the OKE lines must not be MODIFIED. Adding around them is supported.
set -euxo pipefail

# ---- Anza host tuning. A container cannot set these. ----
cat >/etc/sysctl.d/21-agave-validator.conf <<'EOF'
net.core.rmem_max = 134217728
net.core.rmem_default = 134217728
net.core.wmem_max = 134217728
net.core.wmem_default = 134217728
vm.max_map_count = 1000000
fs.nr_open = 1000000
net.netfilter.nf_conntrack_max = 1048576
EOF
sysctl -p /etc/sysctl.d/21-agave-validator.conf
echo '* - nofile 1000000' >/etc/security/limits.d/90-solana-nofiles.conf

# ---- Container runtime rlimits ----
# Kubernetes has NO pod-spec field for rlimits (kubernetes/kubernetes#3595, open since 2015).
# containerd 1.8+ leaves LimitNOFILE unset, so containers inherit soft 1024 / hard 524288.
# Agave 3.0+ makes memlock a hard startup requirement.
mkdir -p /etc/systemd/system/containerd.service.d
cat >/etc/systemd/system/containerd.service.d/10-solana-limits.conf <<'EOF'
[Service]
LimitNOFILE=1000000
LimitMEMLOCK=infinity
EOF
systemctl daemon-reload

# ---- Host firewall ----
# OCI's Oracle Linux and Ubuntu images terminate filter/INPUT with:
#     REJECT --reject-with icmp-host-prohibited
# This bites ONLY hostNetwork pods. ClusterIP traffic traverses FORWARD and is unaffected — which
# is exactly why a ClusterIP test Service will "prove" networking works while gossip peers sit
# at 0 and nothing in the pod status or the validator log points at the firewall.
SOLANA_PORTS="8000:8026"
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-port=8000-8026/udp
  firewall-cmd --permanent --add-port=8000-8026/tcp
  firewall-cmd --reload
else
  # -I inserts at position 1, ahead of the REJECT.
  # -A appends AFTER it and does nothing at all. That single character is an evening.
  iptables -I INPUT 1 -p udp --dport ${SOLANA_PORTS} -j ACCEPT
  iptables -I INPUT 1 -p tcp --dport ${SOLANA_PORTS} -j ACCEPT
  if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save
  elif [ -d /etc/iptables ]; then
    iptables-save >/etc/iptables/rules.v4
  else
    iptables-save >/etc/sysconfig/iptables
  fi
fi

# Record the before/after for docs/evidence/network/
iptables -L INPUT -n -v --line-numbers >/var/log/solana-iptables-after.log || true

# ---- OKE default bootstrap: DO NOT MODIFY ----
curl --fail -H "Authorization: Bearer Oracle" -L0 \
  http://169.254.169.254/opc/v2/instance/metadata/oke_init_script \
  | base64 --decode > /var/run/oke-init.sh
bash /var/run/oke-init.sh
# ---- end OKE default bootstrap ----
