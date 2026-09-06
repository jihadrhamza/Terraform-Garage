###############################################################################
# phase3/variables.tf
###############################################################################

variable "aws_access_key" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name - must match the value used in Phase 1"
  type        = string
}

variable "environment" {
  description = "Environment label (sandbox, staging, production)"
  type        = string
  default     = "sandbox"
}

variable "deployment_suffix" {
  description = <<-EOT
    Optional suffix appended to the CodeBuild project name (e.g. "v2", "retry1").
    Bump this to sidestep a stale GitHub Actions webhook left over from a
    previous run/account without needing to delete it from GitHub first.
  EOT
  type        = string
  default     = ""
}

variable "github_organization" {
  description = "GitHub organization name or username (e.g. Books-POCGroups)"
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

variable "build_timeout" {
  description = "Maximum build duration in minutes"
  type        = number
  default     = 60
}

variable "compute_type" {
  description = "CodeBuild compute type: BUILD_GENERAL1_SMALL, MEDIUM, LARGE, XLARGE"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
