###############################################################################
# phase3/codebuild/outputs.tf
###############################################################################

output "codebuild_project_name" {
  description = "Name of the CodeBuild runner project"
  value       = aws_codebuild_project.runner.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild runner project"
  value       = aws_codebuild_project.runner.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = aws_iam_role.codebuild.arn
}

output "codebuild_sg_id" {
  description = "Security group ID attached to the CodeBuild VPC runner"
  value       = aws_security_group.codebuild.id
}

output "github_repository_url" {
  description = "Full GitHub repository URL used as the build source"
  value       = local.github_repo_url
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for build output"
  value       = aws_cloudwatch_log_group.codebuild.name
}

output "ecr_registry" {
  description = "ECR registry base URL"
  value       = local.ecr_registry
}

output "runs_on_label" {
  description = "Base label for GitHub Actions runs-on"
  value       = "codebuild-${local.name_prefix}-runner"
}
