###############################################################################
# modules/kubectl-instance/variables.tf
###############################################################################

variable "project_name"         { type = string }
variable "environment"          { type = string }
variable "vpc_id"               { type = string }
variable "public_subnet_id"     { type = string }
variable "cluster_name"         { type = string }
variable "cluster_endpoint"     { type = string }
variable "cluster_ca"           { type = string }
variable "aws_region"           { type = string }
variable "instance_type"        { type = string }
variable "eks_node_role_arn"    { type = string }
variable "eks_cluster_role_arn" { type = string }

variable "kubectl_sg_id" {
  description = "Security group ID for the kubectl instance"
  type        = string
}
