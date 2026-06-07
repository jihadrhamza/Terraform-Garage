###############################################################################
# modules/kubectl-instance/main.tf
# EC2 management instance - no SSH key, access via SSM Session Manager only
###############################################################################

# --- Latest Amazon Linux 2 AMI ----------------------------------------------
data "aws_ssm_parameter" "al2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# --- IAM Role for the instance ----------------------------------------------
resource "aws_iam_role" "kubectl" {
  name = "${var.project_name}-${var.environment}-kubectl-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM - mandatory for Session Manager access
resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.kubectl.name
}

# Allow the instance to call eks:DescribeCluster (needed for kubeconfig)
resource "aws_iam_role_policy" "eks_describe" {
  name = "eks-describe"
  role = aws_iam_role.kubectl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        # Needed so the instance can update kubeconfig via aws cli
        Effect   = "Allow"
        Action   = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "kubectl" {
  name = "${var.project_name}-${var.environment}-kubectl-profile"
  role = aws_iam_role.kubectl.name
}

# Security group is created in root main.tf to avoid circular dependency
# (EKS cluster SG needs kubectl SG ID before kubectl instance is created)

# --- EC2 Instance -----------------------------------------------------------
resource "aws_instance" "kubectl" {
  ami                    = data.aws_ssm_parameter.al2_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.kubectl_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.kubectl.name

  # No key_name - access exclusively via SSM Session Manager
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
  }))

  tags = {
    Name = "${var.project_name}-${var.environment}-kubectl"
  }
}
