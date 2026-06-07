#!/bin/bash
###############################################################################
# clean.sh - Remove Terraform state, lock, and cache from all phases
# Usage: chmod +x clean.sh && ./clean.sh
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn "This will delete all Terraform state, lock files, and cached providers."
warn "AWS resources will NOT be deleted — only local Terraform tracking files."
echo ""
read -rp "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { info "Aborted."; exit 0; }

for PHASE in phase1 phase2 phase3; do
  DIR="$SCRIPT_DIR/$PHASE"
  if [ ! -d "$DIR" ]; then
    warn "$PHASE/ directory not found — skipping"
    continue
  fi

  info "Cleaning $PHASE/..."
  rm -rf  "$DIR/.terraform"
  rm -f   "$DIR/.terraform.lock.hcl"
  rm -f   "$DIR/terraform.tfstate"
  rm -f   "$DIR/terraform.tfstate.backup"
  rm -f   "$DIR/.terraform.tfstate.lock.info"
  rm -f   "$DIR/terraform.tfplan"
  rm -f   "$DIR/phase1.tfplan"
  rm -f   "$DIR/phase2.tfplan"
  rm -f   "$DIR/phase3.tfplan"
  info "$PHASE/ cleaned"
done

echo ""
info "Done. Run 'terraform init' in each phase before applying."
