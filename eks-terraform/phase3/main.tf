###############################################################################
# PHASE 3 - CodeBuild GitHub Actions Runner Agent
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "phase1" {
  backend = "local"
  config = {
    path = "${path.module}/../phase1/terraform.tfstate"
  }
}

locals {
  cluster_name       = data.terraform_remote_state.phase1.outputs.cluster_name
  vpc_id             = data.terraform_remote_state.phase1.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.phase1.outputs.private_subnet_ids
  node_role_arn      = data.terraform_remote_state.phase1.outputs.node_role_arn
  aws_account_id     = data.aws_caller_identity.current.account_id
}

module "codebuild" {
  source = "./codebuild"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  aws_account_id      = local.aws_account_id
  github_organization = var.github_organization
  github_repository   = var.github_repository
  github_branch       = var.github_branch
  github_token        = var.github_token

  cluster_name       = local.cluster_name
  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids
  node_role_arn      = local.node_role_arn

  log_retention_days = var.log_retention_days
  build_timeout      = var.build_timeout
  compute_type       = var.compute_type

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Phase       = "3"
  }
}

resource "aws_eks_access_entry" "codebuild_runner" {
  cluster_name  = local.cluster_name
  principal_arn = module.codebuild.codebuild_role_arn
  type          = "STANDARD"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Phase       = "3"
  }

  depends_on = [module.codebuild]
}

resource "aws_eks_access_policy_association" "codebuild_runner_admin" {
  cluster_name  = local.cluster_name
  principal_arn = module.codebuild.codebuild_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.codebuild_runner]
}
