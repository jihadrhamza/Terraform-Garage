#!/bin/bash
###############################################################################
# deploy.sh  -  Full deployment: Phase 1 → Phase 2 → Phase 3
#
# Phase 1: VPC, EKS cluster, node group, kubectl EC2 instance, ALB, ACM
# Phase 2: ALB Ingress Controller (Helm), kubeconfig setup via SSM
# Phase 3: CodeBuild GitHub Actions runner agent (ECR/EKS/RDS/ElastiCache/DynamoDB)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh             # deploy all three phases
#   ./deploy.sh --skip-p3   # deploy phase1 + phase2 only
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}  $1${NC}"; \
            echo -e "${CYAN}══════════════════════════════════════════════${NC}\n"; }

SKIP_PHASE3=false
for arg in "$@"; do
  [[ "$arg" == "--skip-p3" ]] && SKIP_PHASE3=true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Pre-flight: ensure tfvars are filled in
# ---------------------------------------------------------------------------
check_creds() {
  local dir=$1
  if grep -qE "PASTE_YOUR|YOUR_GITHUB" "$dir/terraform.tfvars" 2>/dev/null; then
    error "Fill in all placeholder values in $dir/terraform.tfvars before running."
  fi
}

check_creds "phase1"
check_creds "phase2"
$SKIP_PHASE3 || check_creds "phase3"

###############################################################################
# PHASE 1 — AWS Infrastructure
###############################################################################
section "PHASE 1: AWS Infrastructure (VPC, EKS, ALB, ACM)"

cd "$SCRIPT_DIR/phase1"
info "Initializing Phase 1..."
terraform init -upgrade -input=false

info "Planning Phase 1..."
terraform plan -out=phase1.tfplan -input=false

info "Applying Phase 1 (~15 min for EKS cluster)..."
terraform apply -input=false phase1.tfplan

info "Phase 1 outputs:"
terraform output kubectl_ssm_command  || true
terraform output kubeconfig_command   || true

###############################################################################
# PHASE 2 — Helm / Kubernetes resources
###############################################################################
section "PHASE 2: Helm / ALB Ingress Controller"

cd "$SCRIPT_DIR/phase2"
info "Initializing Phase 2..."
terraform init -upgrade -input=false

info "Planning Phase 2..."
terraform plan -out=phase2.tfplan -input=false

info "Applying Phase 2..."
terraform apply -input=false phase2.tfplan

###############################################################################
# PHASE 3 — CodeBuild GitHub Actions Runner
###############################################################################
if $SKIP_PHASE3; then
  warn "Skipping Phase 3 (--skip-p3 flag set)."
else
  section "PHASE 3: CodeBuild GitHub Actions Runner Agent"

  cd "$SCRIPT_DIR/phase3"
  info "Initializing Phase 3..."
  terraform init -upgrade -input=false

  info "Planning Phase 3..."
  terraform plan -out=phase3.tfplan -input=false

  info "Applying Phase 3..."
  terraform apply -input=false phase3.tfplan

  info "Phase 3 outputs:"
  CODEBUILD_PROJECT=$(terraform output -raw codebuild_project_name 2>/dev/null || echo "")
  CODEBUILD_ROLE=$(terraform output -raw codebuild_role_arn       2>/dev/null || echo "")
  WEBHOOK_URL=$(terraform output -raw webhook_payload_url         2>/dev/null || echo "")
  LOG_GROUP=$(terraform output -raw cloudwatch_log_group          2>/dev/null || echo "")

  echo ""
  echo "  CodeBuild project : $CODEBUILD_PROJECT"
  echo "  CodeBuild IAM role: $CODEBUILD_ROLE"
  echo "  Webhook URL       : $WEBHOOK_URL"
  echo "  CloudWatch logs   : $LOG_GROUP"
  echo ""

  # -------------------------------------------------------------------------
  # Grant the CodeBuild role EKS cluster-admin access via EKS Access Entry API
  # This uses AWS CLI — no eksctl required.
  # -------------------------------------------------------------------------
  section "Granting CodeBuild runner EKS cluster-admin access"

  CLUSTER_NAME=$(cd "$SCRIPT_DIR/phase1" && terraform output -raw cluster_name 2>/dev/null || echo "")
  AWS_REGION=$(cd "$SCRIPT_DIR/phase1" && terraform output -raw aws_region     2>/dev/null || \
               grep 'aws_region' "$SCRIPT_DIR/phase1/terraform.tfvars" | awk -F'"' '{print $2}')

  if [[ -z "$CLUSTER_NAME" || -z "$CODEBUILD_ROLE" ]]; then
    warn "Could not determine cluster name or CodeBuild role ARN — skipping EKS access entry."
    warn "Run manually:  terraform output -raw eks_auth_patch_command  (in phase3/)"
  else
    # Source AWS creds from phase1 tfvars so the CLI call works without env vars
    AWS_ACCESS_KEY=$(grep 'aws_access_key' "$SCRIPT_DIR/phase1/terraform.tfvars" | awk -F'"' '{print $2}')
    AWS_SECRET_KEY=$(grep 'aws_secret_key' "$SCRIPT_DIR/phase1/terraform.tfvars" | awk -F'"' '{print $2}')

    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_KEY"
    export AWS_DEFAULT_REGION="$AWS_REGION"

    info "Creating EKS access entry for CodeBuild role..."
    # create-access-entry is idempotent — safe to re-run
    aws eks create-access-entry \
      --cluster-name  "$CLUSTER_NAME" \
      --principal-arn "$CODEBUILD_ROLE" \
      --type          STANDARD \
      --region        "$AWS_REGION" 2>/dev/null || \
      warn "Access entry may already exist — continuing."

    info "Associating AmazonEKSClusterAdminPolicy..."
    aws eks associate-access-policy \
      --cluster-name  "$CLUSTER_NAME" \
      --principal-arn "$CODEBUILD_ROLE" \
      --policy-arn    "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" \
      --access-scope  type=cluster \
      --region        "$AWS_REGION" 2>/dev/null || \
      warn "Policy association may already exist — continuing."

    info "EKS access entry created. Verifying..."
    aws eks list-access-entries \
      --cluster-name "$CLUSTER_NAME" \
      --region       "$AWS_REGION" \
      --query        "accessEntries[?contains(@, 'codebuild')]" \
      --output       table 2>/dev/null || true

    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
  fi
fi

###############################################################################
# Summary
###############################################################################
section "Deployment Complete"

cd "$SCRIPT_DIR/phase1"
info "Connect to kubectl instance:"
terraform output -raw kubectl_ssm_command 2>/dev/null || true

echo ""
if ! $SKIP_PHASE3; then
  cd "$SCRIPT_DIR/phase3"
  info "CodeBuild runner project:"
  terraform output -raw codebuild_project_name 2>/dev/null || true
  echo ""
  info "Add this workflow runs-on to your GitHub Actions:"
  PROJECT=$(terraform output -raw codebuild_project_name 2>/dev/null || echo "<project>")
  ORG=$(grep 'github_organization' terraform.tfvars | awk -F'"' '{print $2}')
  REPO=$(grep 'github_repository'  terraform.tfvars | awk -F'"' '{print $2}')
  echo "  runs-on: codebuild-${ORG}-${REPO}-\${{ github.run_id }}-\${{ github.run_attempt }}"
fi

echo ""
info "Done. See README.md for next steps."
