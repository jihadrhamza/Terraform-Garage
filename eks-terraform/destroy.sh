#!/bin/bash
###############################################################################
# destroy.sh  -  Tears down Phase 3 → Phase 2 → Phase 1 in correct order
#
# Usage:
#   chmod +x destroy.sh
#   ./destroy.sh             # destroy all three phases
#   ./destroy.sh --skip-p3   # destroy phase2 + phase1 only
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

warn "This will DESTROY all infrastructure. You have 10 seconds to abort (Ctrl-C)..."
sleep 10

###############################################################################
# PHASE 3 — CodeBuild runner (destroy first)
###############################################################################
if $SKIP_PHASE3; then
  warn "Skipping Phase 3 destroy (--skip-p3 flag set)."
elif [[ -f "phase3/terraform.tfstate" ]] || [[ -d "phase3/.terraform" ]]; then
  section "Destroying Phase 3: CodeBuild Runner"

  # Remove the EKS access entry for the CodeBuild role before destroying
  # so EKS doesn't hold a reference to the IAM role.
  CODEBUILD_ROLE=$(cd phase3 && terraform output -raw codebuild_role_arn 2>/dev/null || echo "")
  CLUSTER_NAME=$(cd phase1  && terraform output -raw cluster_name        2>/dev/null || echo "")
  AWS_REGION=$(grep 'aws_region' phase1/terraform.tfvars | awk -F'"' '{print $2}')
  AWS_ACCESS_KEY=$(grep 'aws_access_key' phase1/terraform.tfvars | awk -F'"' '{print $2}')
  AWS_SECRET_KEY=$(grep 'aws_secret_key' phase1/terraform.tfvars | awk -F'"' '{print $2}')

  if [[ -n "$CODEBUILD_ROLE" && -n "$CLUSTER_NAME" ]]; then
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_KEY"
    export AWS_DEFAULT_REGION="$AWS_REGION"

    info "Removing EKS access entry for CodeBuild role..."
    aws eks delete-access-entry \
      --cluster-name  "$CLUSTER_NAME" \
      --principal-arn "$CODEBUILD_ROLE" \
      --region        "$AWS_REGION" 2>/dev/null || \
      warn "EKS access entry not found or already removed — continuing."

    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
  fi

  cd "$SCRIPT_DIR/phase3"
  terraform destroy -auto-approve -input=false
  cd "$SCRIPT_DIR"
else
  warn "Phase 3 state not found — skipping."
fi

###############################################################################
# PHASE 2 — Helm / Kubernetes resources
###############################################################################
section "Destroying Phase 2: Helm / ALB Controller"
cd "$SCRIPT_DIR/phase2"
terraform destroy -auto-approve -input=false
cd "$SCRIPT_DIR"

###############################################################################
# PHASE 1 — AWS Infrastructure
###############################################################################
section "Destroying Phase 1: AWS Infrastructure"
cd "$SCRIPT_DIR/phase1"
terraform destroy -auto-approve -input=false
cd "$SCRIPT_DIR"

###############################################################################
# Done
###############################################################################
section "All resources destroyed"
info "Verify in AWS Console that no orphaned resources remain:"
info "  • EKS clusters"
info "  • VPCs / Subnets"
info "  • CodeBuild projects"
info "  • ECR repositories (not managed by Terraform — delete manually if needed)"
