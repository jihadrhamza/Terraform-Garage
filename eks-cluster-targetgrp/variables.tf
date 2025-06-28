variable "region" {
  default     = "us-east-1"
  description = "aws region"
}

variable "access_key" {
  default = ""
}

variable "secret_key" {
  default = ""
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version."
  type        = string
}
