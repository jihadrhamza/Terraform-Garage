#!/bin/bash
set -euo pipefail
exec > /var/log/userdata.log 2>&1

echo "=== Starting kubectl instance bootstrap ==="

# --- Update system ----------------------------------------------------------
yum update -y

# --- Install AWS CLI v2 -----------------------------------------------------
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# --- Install kubectl --------------------------------------------------------
KUBECTL_VERSION="v1.29.3"
curl -fsSLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# --- Install Helm -----------------------------------------------------------
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# --- Install eksctl ---------------------------------------------------------
curl -fsSL \
  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" \
  | tar -xz -C /tmp
mv /tmp/eksctl /usr/local/bin/eksctl
chmod +x /usr/local/bin/eksctl

# --- Wait for EKS cluster to be ACTIVE then configure kubectl ---------------
# Retries every 15 seconds for up to 20 minutes
echo "Waiting for EKS cluster ${cluster_name} to become ACTIVE..."
MAX_ATTEMPTS=80
ATTEMPT=0
until aws eks describe-cluster \
        --name "${cluster_name}" \
        --region "${aws_region}" \
        --query "cluster.status" \
        --output text 2>/dev/null | grep -q "^ACTIVE$"; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    echo "ERROR: Timed out waiting for cluster to become ACTIVE"
    exit 1
  fi
  echo "Attempt $${ATTEMPT}/$${MAX_ATTEMPTS} - cluster not ready yet, waiting 15s..."
  sleep 15
done

echo "Cluster is ACTIVE. Configuring kubectl..."

# Configure for ssm-user (the SSM session user)
mkdir -p /home/ssm-user/.kube
aws eks update-kubeconfig \
  --name "${cluster_name}" \
  --region "${aws_region}" \
  --kubeconfig /home/ssm-user/.kube/config
chown -R ssm-user:ssm-user /home/ssm-user/.kube

# Configure for ec2-user
mkdir -p /home/ec2-user/.kube
aws eks update-kubeconfig \
  --name "${cluster_name}" \
  --region "${aws_region}" \
  --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube

# Configure for root
aws eks update-kubeconfig \
  --name "${cluster_name}" \
  --region "${aws_region}"

echo "kubectl configured successfully"

# --- Handy aliases for all users --------------------------------------------
for BASHRC in /home/ssm-user/.bashrc /home/ec2-user/.bashrc /root/.bashrc; do
  cat >> "$BASHRC" << ALIASES
alias k='kubectl'
alias kgp='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc -A'
export AWS_DEFAULT_REGION=${aws_region}
ALIASES
done

echo "=== kubectl instance bootstrap complete ==="
