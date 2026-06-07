###############################################################################
# phase3/codebuild/locals.tf
###############################################################################

locals {
  github_repo_url = "https://github.com/${var.github_organization}/${var.github_repository}.git"
  name_prefix     = "${var.project_name}-${var.environment}"
  ecr_registry    = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
