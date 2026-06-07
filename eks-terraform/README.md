# EKS Terraform — Full Deployment (Phase 1 → 2 → 3)

Three-phase Terraform project that provisions a complete AWS EKS platform
with an automated GitHub Actions CI/CD pipeline powered by AWS CodeBuild.

---

## Architecture

```
Phase 1 — AWS Infrastructure
  VPC (3 public + 3 private subnets)
  EKS cluster + managed node group
  kubectl EC2 management instance (SSM access)
  ALB + security groups + ACM certificate
  IAM roles (node, ALB controller, kubectl, CodeBuild)

Phase 2 — Kubernetes Bootstrap
  AWS Load Balancer Controller (Helm)
  ALB-resident Ingress (HTTP→HTTPS redirect, /health endpoint)
  kubeconfig setup on kubectl instance via SSM

Phase 3 — CI/CD Runner
  CodeBuild project = GitHub Actions self-hosted runner
  IAM role with full access to:
    ECR, EKS, RDS/Aurora, ElastiCache, DynamoDB,
    Secrets Manager, SSM, S3, CloudWatch, KMS
  GitHub webhook (push + PR trigger)
  EKS access entry (cluster-admin for the runner role)
```

---

## Quick start

### 1. Fill in credentials

```bash
# Phase 1 — AWS infra + EKS settings
vim phase1/terraform.tfvars

# Phase 2 — same AWS credentials
vim phase2/terraform.tfvars

# Phase 3 — AWS credentials + GitHub org/repo/token
vim phase3/terraform.tfvars
```

**Phase 3 key variables:**

| Variable | Description |
|---|---|
| `github_organization` | Your GitHub org name or username |
| `github_repository` | Repository name (without org prefix) |
| `github_token` | PAT with `repo`, `admin:repo_hook`, `workflow` scopes |

### 2. Deploy everything

```bash
chmod +x deploy.sh destroy.sh
./deploy.sh
```

Or deploy phases individually (must be in order):

```bash
cd phase1 && terraform init && terraform apply
cd ../phase2 && terraform init && terraform apply
cd ../phase3 && terraform init && terraform apply
```

### 3. Wire your GitHub Actions workflow

Copy `phase3/sample-github-workflow.yml` to your app repo:

```bash
cp phase3/sample-github-workflow.yml \
   /path/to/your-app-repo/.github/workflows/deploy.yml
```

Set these repository secrets in GitHub (Settings → Secrets):

| Secret | Value |
|---|---|
| `AWS_REGION` | e.g. `us-east-1` |
| `AWS_ACCOUNT_ID` | 12-digit account ID |
| `ECR_REPO_NAME` | Your ECR repository name |
| `IMAGE_NAME` | Docker image name |
| `EKS_CLUSTER_NAME` | From `terraform output cluster_name` in phase1 |

---

## How the GitHub Actions runner works

The `runs-on` value in your workflow routes jobs to CodeBuild:

```yaml
runs-on: codebuild-<org>-<repo>-${{ github.run_id }}-${{ github.run_attempt }}
```

No `buildspec.yaml` is needed. CodeBuild is purely the compute host;
GitHub Actions orchestrates all build and deploy steps.

**Build flow:**
```
Push to main
  → GitHub webhook → CodeBuild starts runner environment
  → GitHub Actions workflow picks up the job
  → Step: docker build
  → Step: docker push to ECR
  → Step: aws eks update-kubeconfig
  → Step: kubectl apply -f k8s/
  → Step: kubectl rollout status
```

---

## Destroy

```bash
./destroy.sh          # tears down phase3 → phase2 → phase1
./destroy.sh --skip-p3  # keep CodeBuild, destroy EKS infra only
```

---

## Directory structure

```
eks-terraform/
├── deploy.sh                    ← Full automated deployment (all 3 phases)
├── destroy.sh                   ← Full teardown (reverse order)
├── README.md
│
├── phase1/                      ← AWS infrastructure
│   ├── main.tf                  (VPC, EKS, ALB, ACM, EKS access entries)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars         ← Fill in your values
│   ├── certs/                   (self-signed TLS cert for ACM)
│   └── modules/
│       ├── vpc/
│       ├── eks/
│       ├── alb/
│       ├── acm/
│       └── kubectl-instance/
│
├── phase2/                      ← Kubernetes bootstrap
│   ├── main.tf                  (Helm ALB controller, SSM kubectl setup)
│   ├── variables.tf
│   └── terraform.tfvars         ← Fill in your values
│
└── phase3/                      ← CodeBuild GitHub Actions runner
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars         ← Fill in your values + GitHub org/repo
    ├── sample-github-workflow.yml
    └── codebuild/
        ├── locals.tf
        ├── variables.tf
        ├── security_group.tf
        ├── iam.tf               (12 permission groups)
        ├── cloudwatch.tf
        ├── codebuild.tf         (project + webhook, no buildspec)
        └── outputs.tf
```

---

## Notes

- `terraform.tfvars` files contain secrets — all are in `.gitignore`.
- Phase 1 pre-declares the CodeBuild IAM role ARN (by convention) so the
  EKS access entry can be created in the same `terraform apply`. If you
  apply phase1 before phase3 exists, target it afterward:
  ```bash
  cd phase1
  terraform apply -target=aws_eks_access_entry.codebuild_runner
  ```
- `deploy.sh` handles this automatically via an AWS CLI fallback.
