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
# common and real on busy regions like eu-frankfurt-1, capacity reservations are unavailable to
# trial accounts, and the home region is fixed at signup.
#
# Verified against the live tenancy on 2026-09-18 (`oci limits value list --service-name compute`):
#   standard-e5-core-count    13   memory 208 GB   <- chosen
#   standard-e3-core-ad-count 16   memory 277 GB   <- fallback, older silicon
#   standard-e2-core-count    13
#   standard-e4-core-count     0   E4 IS UNAVAILABLE, not merely capped
#   standard-e6-core-count     0   (only -reserved- is non-zero)
#   standard-a1/a2/a4          >0  but ARM: no Agave arm64 Linux binary exists. Unusable.
# Fallback order: E5 -> E3. See ADR 0010.
variable "node_shape" {
  type    = string
  default = "VM.Standard.E5.Flex"
}

# 8 of the 13 available OCPUs. Not the maximum: at 13/208 the burn is ~$19.4/day, which would
# exceed the credit balance over the remaining trial. 8/96 is ~$10.4/day and is already well
# above Agave's testnet needs. See docs/cost-report.md.
variable "node_ocpus" {
  type    = number
  default = 8
}

variable "node_memory_gb" {
  type    = number
  default = 96
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

# Budgets are created in the root compartment. Defaults to compartment_id, which is correct when
# you are working directly in the tenancy root as a trial account normally does.
variable "tenancy_ocid" {
  type    = string
  default = ""
}

variable "budget_amount" {
  type        = number
  description = "Budget ceiling in the tenancy's currency (EUR for this tenancy)."
  default     = 250
}

variable "budget_alert_email" {
  type        = list(string)
  description = "Addresses to notify on budget alerts."
  default     = []
}
