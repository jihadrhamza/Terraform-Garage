###############################################################################
# modules/alb/variables.tf
###############################################################################

variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "cluster_name"      { type = string }
variable "certificate_arn"   { type = string }
variable "aws_account_id"    { type = string }
variable "aws_region"        { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
