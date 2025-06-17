###############################################
# variables.tf
###############################################

variable "region" {
  default = "us-east-1"
  description = "aws region"
}

variable "access_key" {
  default = ""
}
variable "secret_key" {
  default = ""
}

variable "kubernetes_version" {
  default     = 1.27
  description = "kubernetes version"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "default CIDR range of the VPC"
}
