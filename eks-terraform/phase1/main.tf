###############################################################################
# PHASE 1 - AWS Infrastructure
# Creates: VPC, EKS cluster + nodes, kubectl EC2 instance, ALB + IAM, ACM cert
# No Kubernetes or Helm providers - zero chicken-and-egg issues.
#
# Run:  terraform init && terraform apply
# Then: cd ../phase2 && terraform init && terraform apply
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_availability_zones" "available" { state = "available" }
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# kubectl Security Group - created here so EKS cluster SG can reference it
# without a circular dependency between the eks and kubectl-instance modules.
# ---------------------------------------------------------------------------
resource "aws_security_group" "kubectl" {
  name        = "${var.project_name}-${var.environment}-kubectl-mgmt-sg"
  description = "kubectl management instance - SSM only, no inbound SSH"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSM and AWS API HTTPS outbound"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All other outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-kubectl-mgmt-sg"
  }

  depends_on = [module.vpc]
}

# --- Modules ----------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = var.cluster_name
}

module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  aws_account_id     = data.aws_caller_identity.current.account_id
  kubectl_sg_id      = aws_security_group.kubectl.id
}

module "kubectl_instance" {
  source = "./modules/kubectl-instance"

  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  public_subnet_id     = module.vpc.public_subnet_ids[0]
  cluster_name         = module.eks.cluster_name
  cluster_endpoint     = module.eks.cluster_endpoint
  cluster_ca           = module.eks.cluster_ca
  aws_region           = var.aws_region
  instance_type        = var.kubectl_instance_type
  eks_node_role_arn    = module.eks.node_role_arn
  eks_cluster_role_arn = module.eks.cluster_role_arn
  kubectl_sg_id        = aws_security_group.kubectl.id
}

# ---------------------------------------------------------------------------
# ACM: Import the self-signed certificate so the ALB can terminate HTTPS.
# ---------------------------------------------------------------------------
module "acm" {
  source = "./modules/acm"

  domain_name            = var.domain_name
  certificate_body_path  = "${path.root}/certs/server.crt"
  private_key_path       = "${path.root}/certs/server.key"
  certificate_chain_path = "${path.root}/certs/rootCA.crt"
}

# ---------------------------------------------------------------------------
# ALB: wire the ACM certificate ARN from the module above (not a tfvar).
# ---------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  cluster_name      = module.eks.cluster_name
  certificate_arn   = module.acm.certificate_arn
  aws_account_id    = data.aws_caller_identity.current.account_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  depends_on = [module.eks, module.acm]
}

# ---------------------------------------------------------------------------
# EKS Access Entries - API-based auth, no aws-auth ConfigMap needed.
# Only resources whose IAM principal EXISTS at phase1 apply time go here.
#
# ✅ kubectl EC2 instance role  — created by module.kubectl_instance above
# ❌ CodeBuild runner role      — created by phase3; lives in phase3/main.tf
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "kubectl" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.kubectl_instance.iam_role_arn
  type          = "STANDARD"
  depends_on    = [module.eks, module.kubectl_instance]
}

resource "aws_eks_access_policy_association" "kubectl_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.kubectl_instance.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on = [aws_eks_access_entry.kubectl]
}

# NOTE: No aws_eks_access_entry for nodes needed here.
# EKS automatically creates the EC2_LINUX access entry for the node role
# when a managed node group is provisioned. Adding it in Terraform causes
# ResourceInUseException (409) on every fresh cluster.
