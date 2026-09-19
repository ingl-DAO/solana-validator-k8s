terraform {
  required_version = ">= 1.9.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.2"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # 3.x. Must match .terraform.lock.hcl, which is committed — a constraint that excludes the
      # locked version fails `terraform init` in CI with "locked provider ... does not match
      # configured version constraint", while working locally because the local .terraform is
      # already populated.
      version = "~> 3.2"
    }
  }
}
