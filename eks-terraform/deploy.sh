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
#   ./deploy.sh                                   # prompts for AWS creds interactively
#   ./deploy.sh --skip-p3                         # deploy phase1 + phase2 only
#   ./deploy.sh --aws-access-key=AKIA... \
#               --aws-secret-key=xxxxx  \
#               --aws-region=us-east-1          # supply creds via flags (no prompt)
#
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_REGION env vars are also
# honored and take precedence over interactive prompts (but not over flags).
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
CLI_ACCESS_KEY=""
CLI_SECRET_KEY=""
CLI_REGION=""

for arg in "$@"; do
  case "$arg" in
    --skip-p3) SKIP_PHASE3=true ;;
    --aws-access-key=*) CLI_ACCESS_KEY="${arg#*=}" ;;
    --aws-secret-key=*) CLI_SECRET_KEY="${arg#*=}" ;;
    --aws-region=*)     CLI_REGION="${arg#*=}" ;;
    *) warn "Unknown argument: $arg" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Collect AWS credentials: flag > env var > interactive prompt
# ---------------------------------------------------------------------------
collect_credentials() {
  AWS_ACCESS_KEY_ID_INPUT="${CLI_ACCESS_KEY:-${AWS_ACCESS_KEY_ID:-}}"
  AWS_SECRET_ACCESS_KEY_INPUT="${CLI_SECRET_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
  AWS_REGION_INPUT="${CLI_REGION:-${AWS_REGION:-}}"

  if [[ -z "$AWS_ACCESS_KEY_ID_INPUT" ]]; then
    read -rp "AWS Access Key ID: " AWS_ACCESS_KEY_ID_INPUT
  fi
  if [[ -z "$AWS_SECRET_ACCESS_KEY_INPUT" ]]; then
    read -rsp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY_INPUT
    echo
  fi
  if [[ -z "$AWS_REGION_INPUT" ]]; then
    read -rp "AWS Region [us-east-1]: " AWS_REGION_INPUT
    AWS_REGION_INPUT="${AWS_REGION_INPUT:-us-east-1}"
  fi

  if [[ -z "$AWS_ACCESS_KEY_ID_INPUT" || -z "$AWS_SECRET_ACCESS_KEY_INPUT" ]]; then
    error "AWS access key and secret key are required."
  fi
}

# ---------------------------------------------------------------------------
# Write/replace a key = "value" line in a tfvars file (adds it if missing)
# ---------------------------------------------------------------------------
set_tfvar() {
  local file="$1" key="$2" value="$3"
  if [[ ! -f "$file" ]]; then
    warn "$file not found — skipping."
    return
  fi
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = \"${value}\"|" "$file"
    rm -f "${file}.bak"
  else
    echo "${key} = \"${value}\"" >> "$file"
  fi
}

update_all_tfvars() {
  local phases=(phase1 phase2)
  $SKIP_PHASE3 || phases+=(phase3)

  for dir in "${phases[@]}"; do
    local f="$SCRIPT_DIR/$dir/terraform.tfvars"
    set_tfvar "$f" "aws_access_key" "$AWS_ACCESS_KEY_ID_INPUT"
    set_tfvar "$f" "aws_secret_key" "$AWS_SECRET_ACCESS_KEY_INPUT"
    set_tfvar "$f" "aws_region"     "$AWS_REGION_INPUT"
    info "Updated AWS credentials in $dir/terraform.tfvars"
  done
}

# ---------------------------------------------------------------------------
# Pre-flight: ensure remaining (non-AWS) tfvars placeholders are filled in
# e.g. github_organization / github_repository in phase3
# ---------------------------------------------------------------------------
check_creds() {
  local dir=$1
  if grep -qE "PASTE_YOUR|YOUR_GITHUB" "$dir/terraform.tfvars" 2>/dev/null; then
    error "Fill in all placeholder values in $dir/terraform.tfvars before running."
  fi
}

section "Collecting AWS credentials"
collect_credentials
update_all_tfvars

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
  AWS_REGION_FOR_EKS=$(cd "$SCRIPT_DIR/phase1" && terraform output -raw aws_region 2>/dev/null || echo "$AWS_REGION_INPUT")

  if [[ -z "$CLUSTER_NAME" || -z "$CODEBUILD_ROLE" ]]; then
    warn "Could not determine cluster name or CodeBuild role ARN — skipping EKS access entry."
    warn "Run manually:  terraform output -raw eks_auth_patch_command  (in phase3/)"
  else
    # Use the credentials collected at the start of this run — no need to
    # re-read them from tfvars.
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID_INPUT"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY_INPUT"
    export AWS_DEFAULT_REGION="$AWS_REGION_FOR_EKS"

    info "Creating EKS access entry for CodeBuild role..."
    # create-access-entry is idempotent — safe to re-run
    aws eks create-access-entry \
      --cluster-name  "$CLUSTER_NAME" \
      --principal-arn "$CODEBUILD_ROLE" \
      --type          STANDARD \
      --region        "$AWS_REGION_FOR_EKS" 2>/dev/null || \
      warn "Access entry may already exist — continuing."

    info "Associating AmazonEKSClusterAdminPolicy..."
    aws eks associate-access-policy \
      --cluster-name  "$CLUSTER_NAME" \
      --principal-arn "$CODEBUILD_ROLE" \
      --policy-arn    "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" \
      --access-scope  type=cluster \
      --region        "$AWS_REGION_FOR_EKS" 2>/dev/null || \
      warn "Policy association may already exist — continuing."

    info "EKS access entry created. Verifying..."
    aws eks list-access-entries \
      --cluster-name "$CLUSTER_NAME" \
      --region       "$AWS_REGION_FOR_EKS" \
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