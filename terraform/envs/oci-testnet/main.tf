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

# `oci session authenticate` produces a SECURITY TOKEN, not an API key. The provider defaults to
# API-key auth, so without these two lines every call fails 401-NotAuthenticated — and the failure
# names the service (Budget, Compute, ...) rather than the credential, which sends you hunting in
# the wrong place.
#
# The profile is NOT necessarily DEFAULT: `oci session authenticate` writes whichever name you
# type, and profile lookup is case-sensitive. `grep '^\[' ~/.oci/config` shows the real names.
provider "oci" {
  region              = var.region
  auth                = var.oci_auth
  config_file_profile = var.oci_config_profile
}

module "oke" {
  source = "../../modules/oci-oke"

  compartment_id      = var.compartment_id
  region              = var.region
  availability_domain = var.availability_domain
  admin_cidr          = var.admin_cidr
  ssh_public_key      = var.ssh_public_key

  # Set to 0 between build sessions. This single variable is the difference between
  # $29.60 and $245 over the remaining trial. See docs/cost-report.md.
  node_pool_size = var.node_pool_size

  budget_amount      = var.budget_amount
  budget_alert_email = var.budget_alert_email
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
