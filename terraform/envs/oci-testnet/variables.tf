variable "compartment_id" {
  type = string
}

variable "region" {
  type = string
}

variable "availability_domain" {
  type = string
}

variable "admin_cidr" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 203.0.113.4/32"
}

variable "ssh_public_key" {
  type = string
}

variable "node_pool_size" {
  type    = number
  default = 1
}

variable "budget_amount" {
  type        = number
  description = "Budget ceiling in the tenancy's currency (EUR here)."
  default     = 250
}

variable "budget_alert_email" {
  type        = list(string)
  description = "Addresses notified at 20% actual, 40% actual, and 80% forecast."
  default     = []
}

variable "oci_auth" {
  type        = string
  description = "SecurityToken for `oci session authenticate` sessions; ApiKey for a config-file key pair."
  default     = "SecurityToken"

  validation {
    condition     = contains(["SecurityToken", "ApiKey", "InstancePrincipal", "ResourcePrincipal"], var.oci_auth)
    error_message = "oci_auth must be SecurityToken, ApiKey, InstancePrincipal or ResourcePrincipal."
  }
}

variable "oci_config_profile" {
  type        = string
  description = "Profile in ~/.oci/config. Case-sensitive, and often NOT DEFAULT."
  default     = "DEFAULT"
}
