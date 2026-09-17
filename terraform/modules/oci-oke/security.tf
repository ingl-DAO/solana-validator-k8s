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
