# Never hardcode the worker image OCID — resolve it for the chosen shape and k8s version.
data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  node_image_id = [
    for s in data.oci_containerengine_node_pool_option.this.sources :
    s.image_id if can(regex("OKE-${replace(var.kubernetes_version, "v", "")}", s.source_name))
  ][0]
}

resource "oci_containerengine_node_pool" "this" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${var.name_prefix}-workers"
  node_shape         = var.node_shape

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_source_details {
    image_id    = local.node_image_id
    source_type = "IMAGE"
    # 60 GB. The other 100 GB of the 200 GB aggregate quota is the ledger PVC, leaving 40 GB of
    # headroom for an in-place expansion. See ADR 0007 for the arithmetic that rejected a second
    # node pool.
    boot_volume_size_in_gbs = 60
  }

  node_config_details {
    size = var.node_pool_size

    # In-transit encryption between the instance and its block volumes. Free, and there is no
    # reason not to. (checkov CKV2_OCI_5)
    is_pv_encryption_in_transit_enabled = true
    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = oci_core_subnet.workers.id
    }
    nsg_ids = [oci_core_network_security_group.workers.id]
    node_pool_pod_network_option_details {
      cni_type = "FLANNEL_OVERLAY"
    }
  }

  initial_node_labels {
    key   = "solana.io/node"
    value = "true"
  }

  ssh_public_key = var.ssh_public_key

  node_metadata = {
    user_data = base64encode(file("${path.module}/cloud-init/worker-init.sh"))
  }
}
