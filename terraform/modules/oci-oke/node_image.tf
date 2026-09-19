# Node image selection, kept in its own file on purpose.
#
# Checkov's HCL parser cannot parse these locals and reports "Error parsing file", which makes it
# skip the ENTIRE file — silently, still exiting 0. With the locals here, nodepool.tf parses and
# the node pool resource is actually scanned. This file declares no resources, so nothing is lost
# by it being skipped. `terraform validate` is happy with either layout; this is purely to stop a
# scanner quietly covering less than it appears to.

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
