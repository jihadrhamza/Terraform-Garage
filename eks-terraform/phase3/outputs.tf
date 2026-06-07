###############################################################################
# phase3/outputs.tf
###############################################################################

output "codebuild_project_name" {
  description = "Name of the CodeBuild runner project"
  value       = module.codebuild.codebuild_project_name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild runner project"
  value       = module.codebuild.codebuild_project_arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role (registered as EKS cluster-admin)"
  value       = module.codebuild.codebuild_role_arn
}

output "codebuild_sg_id" {
  description = "Security group ID attached to the CodeBuild VPC runner"
  value       = module.codebuild.codebuild_sg_id
}

output "github_repository_url" {
  description = "GitHub repository URL the runner is registered against"
  value       = module.codebuild.github_repository_url
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for build output"
  value       = module.codebuild.cloudwatch_log_group
}

output "ecr_registry" {
  description = "ECR registry base URL to use in GitHub Actions workflows"
  value       = module.codebuild.ecr_registry
}

output "runs_on_label" {
  description = "Base label for GitHub Actions runs-on - append github.run_id and github.run_attempt"
  value       = module.codebuild.runs_on_label
}
