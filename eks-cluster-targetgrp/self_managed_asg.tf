data "aws_ssm_parameter" "eks_worker_ami" {
  name = "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "eks_workers" {
  name_prefix   = "eks-worker-"
  image_id      = data.aws_ssm_parameter.eks_worker_ami.value
  instance_type = "t2.micro"
  key_name      = aws_key_pair.eks_key.key_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "eks_workers" {
  name_prefix          = "eks-workers-"
  max_size             = 2
  min_size             = 2
  desired_capacity     = 2
  vpc_zone_identifier  = [for s in aws_subnet.eks_subnet : s.id]
  launch_template {
    id      = aws_launch_template.eks_workers.id
    version = "$Latest"
  }
  target_group_arns    = [aws_lb_target_group.nginx_tg.arn]
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "tls_private_key" "eks_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "eks_key" {
  key_name   = "eks-key"
  public_key = tls_private_key.eks_key.public_key_openssh
}

output "eks_private_key_pem" {
  value     = tls_private_key.eks_key.private_key_pem
  sensitive = true
}

resource "aws_instance" "jump_server" {
  ami                    = data.aws_ssm_parameter.eks_worker_ami.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.eks_subnet[0].id
  key_name               = aws_key_pair.eks_key.key_name
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.jump_server.id]

  user_data = <<-EOF
    #!/bin/bash
    exec > /var/log/user-data.log 2>&1
    set -x
    yum update -y
    yum install -y curl unzip
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    # Install latest kubectl
    curl -Lo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl
    chmod +x /usr/local/bin/kubectl
    export PATH=$PATH:/usr/local/bin
    echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile
    which kubectl
    kubectl version --client || true
  EOF

  tags = {
    Name = "eks-jump-server"
  }
}

resource "aws_security_group" "jump_server" {
  name        = "eks-jump-server-sg"
  description = "Allow SSH and EKS API access from anywhere (for demo, restrict in production)"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
