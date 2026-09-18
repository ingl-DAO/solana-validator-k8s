resource "oci_containerengine_cluster" "this" {
  #checkov:skip=CKV2_OCI_6:PodSecurityPolicy was deprecated in Kubernetes 1.21 and REMOVED in 1.25. This cluster runs 1.31, where the resource does not exist. The check is obsolete; the successor (Pod Security Admission) is enforced by namespace label, not cluster config.

  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${var.name_prefix}-oke"
  vcn_id             = oci_core_vcn.this.id

  # BASIC, not ENHANCED. The Basic control plane is $0; Enhanced is $0.10/hr and buys nothing
  # this project uses. Trial accounts are capped at one Basic cluster per region. See ADR 0002.
  type = "BASIC_CLUSTER"

  endpoint_config {
    subnet_id            = oci_core_subnet.api.id
    is_public_ip_enabled = true
    nsg_ids              = [oci_core_network_security_group.api.id]
  }

  options {
    service_lb_subnet_ids = []
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}
