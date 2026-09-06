###############################################################################
# phase3/codebuild/variables.tf
###############################################################################

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "sandbox"
}

variable "deployment_suffix" {
  description = <<-EOT
    Optional suffix appended to the CodeBuild project name (e.g. "v2", "retry1").
    GitHub Actions webhooks are keyed by (repo, CodeBuild project name), so if a
    prior run already registered a webhook for this repo under the current
    name and you can't delete it right now, bump this value to get a fresh,
    non-colliding project name without touching GitHub.
  EOT
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_organization" {
  description = "GitHub organization name or username"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name without the org prefix"
  type        = string
}

variable "github_branch" {
  description = "Default branch of the repository"
  type        = string
  default     = "main"
}

variable "github_token" {
  description = "GitHub personal access token (scopes: repo, admin:repo_hook, workflow)"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the CodeBuild VPC config"
  type        = list(string)
}

variable "node_role_arn" {
  description = "EKS node IAM role ARN"
  type        = string
}

variable "build_timeout" {
  description = "Maximum build duration in minutes"
  type        = number
  default     = 60
}

variable "compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
