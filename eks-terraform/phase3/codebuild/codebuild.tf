###############################################################################
# phase3/codebuild/codebuild.tf
#
# CodeBuild GitHub Actions self-hosted runner using PAT authentication.
#
# The GitHub App (CodeStar Connections) approach was abandoned because:
#   - aws_codestarconnections_resource_policy does not exist in the provider
#   - CodeBuild webhook creation with WORKFLOW_JOB_QUEUED requires the
#     connection resource policy which cannot be set via Terraform
#
# PAT-based auth works cleanly with WORKFLOW_JOB_QUEUED webhook filter
# which is what registers this as a GitHub Actions runner project.
###############################################################################

# ---------------------------------------------------------------------------
# GitHub PAT source credential
# One credential per server_type per region. Terraform updates in place
# if one already exists - safe to re-run.
# ---------------------------------------------------------------------------
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}

# ---------------------------------------------------------------------------
# CodeBuild project
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "runner" {
  name          = "${local.name_prefix}-runner"
  description   = "GitHub Actions self-hosted runner for ${var.github_organization}/${var.github_repository}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = var.build_timeout

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = var.compute_type
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = var.cluster_name
    }
    environment_variable {
      name  = "ECR_REGISTRY"
      value = local.ecr_registry
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = var.environment
    }
    environment_variable {
      name  = "GITHUB_ORGANIZATION"
      value = var.github_organization
    }
    environment_variable {
      name  = "GITHUB_REPOSITORY"
      value = var.github_repository
    }
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnet_ids
    security_group_ids = [aws_security_group.codebuild.id]
  }

  source {
    type            = "GITHUB"
    location        = local.github_repo_url
    git_clone_depth = 1

    report_build_status = false
  }

  source_version = var.github_branch

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "runner"
      status      = "ENABLED"
    }
  }

  depends_on = [aws_codebuild_source_credential.github]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Webhook with WORKFLOW_JOB_QUEUED filter.
# This is what registers the project as a GitHub Actions runner in AWS Console.
# GitHub dispatches jobs to this runner when workflow uses:
#   runs-on: codebuild-<project-name>-${{ github.run_id }}-${{ github.run_attempt }}
# ---------------------------------------------------------------------------
resource "aws_codebuild_webhook" "runner" {
  project_name = aws_codebuild_project.runner.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
  }
}
