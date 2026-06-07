###############################################################################
# modules/acm/variables.tf
###############################################################################

variable "domain_name" {
  type = string
}

variable "certificate_body_path" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "certificate_chain_path" {
  type = string
}