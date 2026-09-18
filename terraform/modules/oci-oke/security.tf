locals {
  p2p_min = 8000
  p2p_max = 8026
}

resource "oci_core_network_security_group" "workers" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-workers"
}

# ---------------------------------------------------------------------------------------------
# Solana P2P. STATELESS, deliberately.
#
# Stateful OCI rules are enforced by a per-VNIC connection-tracking table whose size is fixed by
# the shape. Solana's UDP volume from thousands of peers fills it, and the result is symptom-free
# packet loss: no error, no counter, no log line, anywhere. Oracle explicitly recommends stateless
# rules for high-volume internet-facing traffic. See docs/decisions/0006.
# ---------------------------------------------------------------------------------------------
resource "oci_core_network_security_group_security_rule" "p2p_udp_in" {
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "Solana P2P UDP (gossip/turbine/repair) - stateless"
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = true
  udp_options {
    destination_port_range {
      min = local.p2p_min
      max = local.p2p_max
    }
  }
}

# A stateless INGRESS rule WITHOUT this companion means replies are silently dropped.
# Everything looks configured. Nothing works.
resource "oci_core_network_security_group_security_rule" "p2p_udp_out" {
  #checkov:skip=CKV2_OCI_2:Egress on 8000-8026 only. 3389 is not in that range; the check is matching the rule type rather than the ports.
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "Required companion egress for stateless UDP ingress"
  direction                 = "EGRESS"
  protocol                  = "17"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = true
  udp_options {
    source_port_range {
      min = local.p2p_min
      max = local.p2p_max
    }
  }
}

resource "oci_core_network_security_group_security_rule" "p2p_tcp_in" {
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "Solana serve-repair / TPU-forwards TCP - stateless"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = true
  tcp_options {
    destination_port_range {
      min = local.p2p_min
      max = local.p2p_max
    }
  }
}

resource "oci_core_network_security_group_security_rule" "p2p_tcp_out" {
  #checkov:skip=CKV2_OCI_2:Egress on 8000-8026 only. 3389 is not in that range; the check is matching the rule type rather than the ports.
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "Required companion egress for stateless TCP ingress"
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = true
  tcp_options {
    source_port_range {
      min = local.p2p_min
      max = local.p2p_max
    }
  }
}

# Exporter scrape. VCN-internal only.
resource "oci_core_network_security_group_security_rule" "exporter_in" {
  #checkov:skip=CKV_OCI_21:Stateless is a mitigation for per-VNIC conntrack exhaustion under Solana's P2P UDP volume. A Prometheus scrape every 15s from inside the VCN cannot exhaust it, and making this stateless would require a companion egress rule for no benefit. Applied deliberately to the P2P range only - see ADR 0006.
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "Prometheus scrape of solana-exporter"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 8080
      max = 8080
    }
  }
}

# SSH, scoped to the operator.
resource "oci_core_network_security_group_security_rule" "ssh_in" {
  #checkov:skip=CKV_OCI_21:See exporter_in. SSH from a single admin CIDR does not generate the connection volume that makes stateless necessary.
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "SSH from admin CIDR only"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.admin_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# General egress for snapshot fetch, package installs, image pulls.
resource "oci_core_network_security_group_security_rule" "all_out" {
  #checkov:skip=CKV2_OCI_2:The check flags outbound 3389 within an all-protocol EGRESS rule. This is egress, not ingress - nothing can reach the node on RDP. Egress is required for snapshot fetch, entrypoint gossip and image pulls.
  network_security_group_id = oci_core_network_security_group.workers.id
  description               = "Egress for snapshot fetch and image pulls"
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# NOTE: 8899 (JSON-RPC) and 8900 (websocket) appear NOWHERE in this file, on purpose.
# The validator binds RPC to 127.0.0.1 and the exporter reaches it over loopback inside the
# shared host network namespace. The port is never on the wire, which is stronger than a
# firewall rule. An open Solana RPC endpoint is a documented abuse vector.


# ---------------------------------------------------------------------------------------------
# Control-plane endpoint NSG. The API server is public (this is a throwaway cluster driven from a
# laptop), so scope it to the operator rather than leaving it open. (checkov CKV2_OCI_3)
# ---------------------------------------------------------------------------------------------
resource "oci_core_network_security_group" "api" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-api"
}

resource "oci_core_network_security_group_security_rule" "api_in" {
  #checkov:skip=CKV_OCI_21:Stateful is correct here. Stateless is a mitigation for the per-VNIC conntrack exhaustion that Solana's UDP volume causes on the P2P range; a handful of kubectl sessions cannot exhaust it, and stateless would need a companion egress rule for no benefit.
  network_security_group_id = oci_core_network_security_group.api.id
  description               = "Kubernetes API from the operator only"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.admin_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_workers_in" {
  #checkov:skip=CKV_OCI_21:See api_in. Stateful is correct for control-plane traffic.
  network_security_group_id = oci_core_network_security_group.api.id
  description               = "Kubernetes API from worker nodes"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_out" {
  #checkov:skip=CKV2_OCI_2:EGRESS to the VCN only, not ingress. The control plane must reach kubelets on arbitrary ports; nothing can reach it on RDP.
  network_security_group_id = oci_core_network_security_group.api.id
  description               = "Control plane egress to workers"
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = var.vcn_cidr
  destination_type          = "CIDR_BLOCK"
}
