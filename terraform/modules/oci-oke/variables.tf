variable "compartment_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "solana"
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "admin_cidr" {
  type        = string
  description = "Your public IP in CIDR form. SSH is scoped to this and nothing else."
}

# Shape and AD are variables from line one, deliberately. "Out of host capacity" on flex shapes is
# common and real on popular regions, capacity reservations are unavailable to trial accounts, and
# the home region is fixed at signup. Fallback order: E4 -> E6 -> E5. See ADR 0010 and the risk
# register in docs/. E4's trial limit bucket is 6 OCPU / 96 GB; E5 and E6 are 6 / 72 GB.
variable "node_shape" {
  type    = string
  default = "VM.Standard.E4.Flex"
}

variable "node_ocpus" {
  type    = number
  default = 6
}

variable "node_memory_gb" {
  type    = number
  default = 64
}

variable "availability_domain" {
  type        = string
  description = "Try each AD in the region before changing shape."
}

variable "kubernetes_version" {
  type    = string
  default = "v1.31.1"
}

# Set to 0 between build sessions. This is the entire cost model: $13.96 instead of $136.12.
variable "node_pool_size" {
  type    = number
  default = 1
}

variable "ssh_public_key" {
  type = string
}
