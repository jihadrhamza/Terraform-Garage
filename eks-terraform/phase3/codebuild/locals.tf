###############################################################################
# phase3/codebuild/locals.tf
###############################################################################

locals {
  github_repo_url = "https://github.com/${var.github_organization}/${var.github_repository}.git"

  # Appends "-<suffix>" only when deployment_suffix is set, so the default
  # behavior (no suffix) is unchanged from before.
  name_prefix = var.deployment_suffix != "" ? "${var.project_name}-${var.environment}-${var.deployment_suffix}" : "${var.project_name}-${var.environment}"

  ecr_registry = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
