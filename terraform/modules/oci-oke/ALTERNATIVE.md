# The module version

[ADR 0003](../../../docs/decisions/0003-hand-rolled-hcl-vs-oke-module.md) records why this module
is hand-written HCL rather than a call to `oracle-terraform-modules/oke/oci`. The short version:
the interesting parts of this infrastructure are the stateless NSG rules and the node cloud-init,
and a module invocation hides exactly those.

For completeness, the equivalent using the official module is roughly:

```hcl
module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "~> 5.5.1"

  compartment_id = var.compartment_id
  region         = var.region

  cluster_name       = "${var.name_prefix}-oke"
  kubernetes_version = var.kubernetes_version
  cluster_type       = "basic"

  # The part that does not survive the abstraction: workers must be PUBLIC (ADR 0009) and the
  # NSG rules must be STATELESS (ADR 0006). Both are expressible, neither is the module default,
  # and the node cloud-init still has to be passed in verbatim anyway.
  worker_pools = {
    solana = {
      shape            = var.node_shape
      ocpus            = var.node_ocpus
      memory           = var.node_memory_gb
      size             = var.node_pool_size
      subnet           = "pub_workers"
      cloud_init       = [{ content = file("${path.module}/cloud-init/worker-init.sh") }]
      allow_autoscaler = false
    }
  }
}
```

Which is shorter, and worse to read if the point is to show someone what the infrastructure does.
