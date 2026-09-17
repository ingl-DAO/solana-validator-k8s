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
