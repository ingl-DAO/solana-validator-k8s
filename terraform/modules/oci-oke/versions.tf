terraform {
  required_version = ">= 1.9.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}
