# Never hardcode the worker image OCID — resolve it for the chosen shape and k8s version.
data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  # Anchored: replace(x, "v", "") would strip every "v" in the string, not just the prefix.
  k8s_version_bare = replace(var.kubernetes_version, "/^v/", "")

  # Image names look like:
  #   Oracle-Linux-9.8-2026.08.14-0-OKE-1.34.10-1699            <- what we want
  #   Oracle-Linux-9.8-aarch64-2026.08.14-0-OKE-1.34.10-1699    <- ARM
  #   Oracle-Linux-9.8-Gen2-GPU-2026.08.14-0-OKE-1.34.10-1699   <- GPU
  #
  # "OKE-" is mid-string, not a prefix. Excluding aarch64 is NOT cosmetic: no linux/aarch64 Agave
  # binary has ever been published (ADR 0004), so an ARM node would come up Ready and then fail to
  # run the workload with an exec-format error that points nowhere near the node image.
  # The trailing "-" after the version stops 1.34.1 matching 1.34.10.
  _matching_images = [
    for s in data.oci_containerengine_node_pool_option.this.sources : s.source_name
    if can(regex("OKE-${local.k8s_version_bare}-", s.source_name))
    && !can(regex("aarch64", s.source_name))
    && !can(regex("GPU", s.source_name))
  ]

  # Newest build date first; names sort lexically by date.
  _sorted_images = reverse(sort(local._matching_images))

  node_image_id = [
    for s in data.oci_containerengine_node_pool_option.this.sources :
    s.image_id if s.source_name == try(local._sorted_images[0], "")
  ][0]
}

# Fail with something readable instead of "the collection has no elements".
check "node_image_available" {
  assert {
    condition     = length(local._matching_images) > 0
    error_message = <<-EOT
      No x86_64 OKE node image for Kubernetes ${var.kubernetes_version}.
      List what this region actually offers:
        oci ce cluster-options get --cluster-option-id all --query 'data."kubernetes-versions"'
      Then set kubernetes_version to one of them.
    EOT
  }
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
