terraform {
  required_version = ">= 1.9.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.2"
    }
  }
  # Created by scripts/bootstrap-state.sh. State is never committed; the repo commits the proof
  # the bucket existed and was emptied. See ADR 0011.
  backend "s3" {}
}

provider "oci" {
  region = var.region
}

module "oke" {
  source = "../../modules/oci-oke"

  compartment_id      = var.compartment_id
  region              = var.region
  availability_domain = var.availability_domain
  admin_cidr          = var.admin_cidr
  ssh_public_key      = var.ssh_public_key

  # Set to 0 between build sessions. This single variable is the difference between
  # $13.96 and $136.12 over the remaining trial. See docs/cost-report.md.
  node_pool_size = var.node_pool_size
}

output "kubeconfig_command" {
  value = module.oke.kubeconfig_command
}

output "storage_class_name" {
  value = module.oke.storage_class_name
}

output "contract_satisfied" {
  value = module.oke.contract_satisfied
}
