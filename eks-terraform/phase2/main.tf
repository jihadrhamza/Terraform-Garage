###############################################################################
# PHASE 2 - Kubernetes / Helm + kubectl instance configuration
#
# ALB ownership: the AWS Load Balancer Controller fully owns the ALB.
# Phase1 provides: ACM cert, IRSA role, security group.
# Phase2 provides: Helm chart + Ingress manifest → controller creates ALB.
#
# Listener setup (all via Ingress annotations, no Terraform aws_lb_listener):
#   HTTP:80   → 301 redirect to HTTPS          (ssl-redirect annotation)
#   HTTPS:443 → default 404 fixed-response     (defaultBackend annotation)
#               /health rule → 200 OK          (actions.health-check)
#   Future microservices add rules via group.name + group.order.
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

data "terraform_remote_state" "phase1" {
  backend = "local"
  config = {
    path = "${path.module}/../phase1/terraform.tfstate"
  }
}

locals {
  cluster_name        = data.terraform_remote_state.phase1.outputs.cluster_name
  cluster_endpoint    = data.terraform_remote_state.phase1.outputs.cluster_endpoint
  cluster_ca          = data.terraform_remote_state.phase1.outputs.cluster_ca
  vpc_id              = data.terraform_remote_state.phase1.outputs.vpc_id
  alb_role_arn        = data.terraform_remote_state.phase1.outputs.alb_controller_role_arn
  alb_sg_id           = data.terraform_remote_state.phase1.outputs.alb_sg_id
  kubectl_instance_id = data.terraform_remote_state.phase1.outputs.kubectl_instance_id
  certificate_arn     = data.terraform_remote_state.phase1.outputs.acm_certificate_arn
  private_subnet_ids  = data.terraform_remote_state.phase1.outputs.private_subnet_ids
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
      env = {
        AWS_ACCESS_KEY_ID     = var.aws_access_key
        AWS_SECRET_ACCESS_KEY = var.aws_secret_key
      }
    }
  }
}

resource "helm_release" "alb_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  version          = "1.7.1"
  create_namespace = false
  wait             = true
  timeout          = 300

  set {
    name  = "clusterName"
    value = local.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = local.alb_role_arn
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = local.vpc_id
  }
}

# ---------------------------------------------------------------------------
# Configure kubectl on the management instance via SSM send-command.
#
# Deploys the alb-resident Ingress which causes the ALB controller to:
#   1. Create one internal ALB (scheme: internal, private subnets)
#   2. Add HTTP:80 listener  → redirect to HTTPS
#   3. Add HTTPS:443 listener → default 404 fixed-response
#   4. Add /health rule       → 200 OK fixed-response (no pod needed)
#
# Future microservices just deploy their own Ingress with:
#   alb.ingress.kubernetes.io/group.name: myapp-sandbox-alb
#   alb.ingress.kubernetes.io/group.order: "200"  (or 300, 400 ...)
# The controller adds their path rules automatically — no Terraform changes.
# ---------------------------------------------------------------------------
resource "null_resource" "configure_kubectl" {
  triggers = {
    instance_id     = local.kubectl_instance_id
    cluster_name    = local.cluster_name
    certificate_arn = local.certificate_arn
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-SHELL
      set -euo pipefail
      INSTANCE_ID="${local.kubectl_instance_id}"
      CLUSTER="${local.cluster_name}"
      REGION="${var.aws_region}"
      CERT_ARN="${local.certificate_arn}"
      ALB_SG="${local.alb_sg_id}"
      SUBNETS="${join(",", local.private_subnet_ids)}"

      echo "==> Waiting for SSM agent on $INSTANCE_ID..."
      for i in $(seq 1 30); do
        STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --query "InstanceInformationList[0].PingStatus" \
          --output text --region $REGION 2>/dev/null || echo "None")
        [ "$STATUS" = "Online" ] && echo "SSM online." && break
        echo "Attempt $i/30 - waiting ($STATUS)..."
        sleep 10
      done

      echo "==> Sending kubeconfig + ingress setup via SSM..."

      cat > /tmp/eks_kubectl_setup.sh << 'SETUPEOF'
#!/bin/bash
set -euo pipefail
CLUSTER="__CLUSTER__"
REGION="__REGION__"
CERT_ARN="__CERT_ARN__"
ALB_SG="__ALB_SG__"
SUBNETS="__SUBNETS__"
echo "Setting up kubeconfig for cluster $CLUSTER in $REGION"

# ssm-user home only exists after first interactive SSM session.
# Create it explicitly so send-command (which runs before any session) works.
id ssm-user &>/dev/null || useradd -m -s /bin/bash ssm-user
HOME_DIR=$(getent passwd ssm-user | cut -d: -f6)
[ -z "$HOME_DIR" ] && HOME_DIR="/home/ssm-user"
mkdir -p "$HOME_DIR"

# kubeconfig for ssm-user
mkdir -p "$HOME_DIR/.kube"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" \
  --kubeconfig "$HOME_DIR/.kube/config"
chown -R ssm-user:ssm-user "$HOME_DIR/.kube"
chmod 700 "$HOME_DIR/.kube"
chmod 600 "$HOME_DIR/.kube/config"

# kubeconfig for root
mkdir -p /root/.kube
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" \
  --kubeconfig /root/.kube/config

# Set env vars so kubectl works in this non-interactive SSM session
export HOME=/root
export KUBECONFIG=/root/.kube/config
export AWS_DEFAULT_REGION="$REGION"

# bashrc aliases
BRCFILE="$HOME_DIR/.bashrc"
touch "$BRCFILE"
grep -qxF "export KUBECONFIG=$HOME_DIR/.kube/config" "$BRCFILE" \
  || echo "export KUBECONFIG=$HOME_DIR/.kube/config" >> "$BRCFILE"
grep -qF "alias k=" "$BRCFILE" || echo "alias k='kubectl'" >> "$BRCFILE"
grep -qF "alias kgn=" "$BRCFILE" || echo "alias kgn='kubectl get nodes'" >> "$BRCFILE"
grep -qF "alias kgp=" "$BRCFILE" || echo "alias kgp='kubectl get pods -A'" >> "$BRCFILE"
chown ssm-user:ssm-user "$BRCFILE"

echo "Done - listing $HOME_DIR/.kube:"
ls -la "$HOME_DIR/.kube/"

# ---------------------------------------------------------------------------
# Deploy alb-resident Ingress.
# This causes the ALB controller to create the ALB with:
#   - scheme: internal          (private, not internet-facing)
#   - subnets: private subnets  (from phase1 VPC)
#   - security-groups: SG from phase1
#   - HTTP:80  → 301 to HTTPS
#   - HTTPS:443 default → 404 fixed-response
#   - /health rule → 200 OK fixed-response (no pod)
#   - deletion_protection: enabled
# ---------------------------------------------------------------------------
echo "==> Deploying ALB ingress with cert ARN: $CERT_ARN"

cat > /tmp/alb-ingress.yaml << MANIFEST
---
apiVersion: v1
kind: Namespace
metadata:
  name: alb-resident

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alb-resident-ingress
  namespace: alb-resident
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/group.name: myapp-sandbox-alb
    alb.ingress.kubernetes.io/group.order: "100"
    alb.ingress.kubernetes.io/security-groups: $ALB_SG
    alb.ingress.kubernetes.io/subnets: $SUBNETS
    alb.ingress.kubernetes.io/load-balancer-attributes: deletion_protection.enabled=true
    alb.ingress.kubernetes.io/actions.health-check: >
      {"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","messageBody":"OK","statusCode":"200"}}
    alb.ingress.kubernetes.io/actions.default-404: >
      {"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","messageBody":"Not Found","statusCode":"404"}}
spec:
  ingressClassName: alb
  defaultBackend:
    service:
      name: default-404
      port:
        name: use-annotation
  rules:
    - http:
        paths:
          - path: /health
            pathType: Prefix
            backend:
              service:
                name: health-check
                port:
                  name: use-annotation
MANIFEST

kubectl apply -f /tmp/alb-ingress.yaml --kubeconfig /root/.kube/config
echo "==> Ingress deployed. Verify with: kubectl get ingress -n alb-resident"
echo "==> ALB provisioning takes ~2 min. Check: kubectl describe ingress alb-resident-ingress -n alb-resident"
SETUPEOF

      # Substitute all placeholders, then base64-encode
      SCRIPT=$(cat /tmp/eks_kubectl_setup.sh \
        | sed "s|__CLUSTER__|$CLUSTER|g" \
        | sed "s|__REGION__|$REGION|g" \
        | sed "s|__CERT_ARN__|$CERT_ARN|g" \
        | sed "s|__ALB_SG__|$ALB_SG|g" \
        | sed "s|__SUBNETS__|$SUBNETS|g")
      echo "$SCRIPT" > /tmp/eks_kubectl_setup_final.sh
      ENCODED=$(base64 < /tmp/eks_kubectl_setup_final.sh | tr -d '\n')

      CMD_JSON=$(printf '{"commands":["echo %s | base64 -d > /tmp/eks_setup.sh","chmod +x /tmp/eks_setup.sh","bash /tmp/eks_setup.sh"]}' "$ENCODED")

      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "$CMD_JSON" \
        --region "$REGION" \
        --query "Command.CommandId" \
        --output text)

      echo "==> SSM Command ID: $COMMAND_ID - waiting for completion..."
      sleep 5

      for i in $(seq 1 24); do
        CMD_STATUS=$(aws ssm get-command-invocation \
          --command-id "$COMMAND_ID" \
          --instance-id "$INSTANCE_ID" \
          --region "$REGION" \
          --query "Status" \
          --output text 2>/dev/null || echo "Pending")
        echo "Status [$i/24]: $CMD_STATUS"
        if [ "$CMD_STATUS" = "Success" ]; then
          echo "==> kubectl configured and ingress deployed successfully!"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region "$REGION" \
            --query "StandardOutputContent" \
            --output text
          exit 0
        elif [ "$CMD_STATUS" = "Failed" ] || [ "$CMD_STATUS" = "Cancelled" ]; then
          echo "==> SSM command failed:"
          aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region "$REGION" \
            --query "StandardErrorContent" \
            --output text
          exit 1
        fi
        sleep 10
      done
      echo "==> Timed out waiting for SSM command"
      exit 1
    SHELL

    environment = {
      AWS_ACCESS_KEY_ID     = var.aws_access_key
      AWS_SECRET_ACCESS_KEY = var.aws_secret_key
      AWS_DEFAULT_REGION    = var.aws_region
    }
  }

  depends_on = [helm_release.alb_controller]
}
