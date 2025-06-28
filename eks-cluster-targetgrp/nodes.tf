data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/1.29/amazon-linux-2/recommended/image_id"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node_role" {
  name               = "eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "node_role_policies" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly"
  ])
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}

resource "aws_iam_instance_profile" "node_profile" {
  name = "eks-node-profile"
  role = aws_iam_role.node_role.name
}

resource "aws_security_group" "node_sg" {
  vpc_id = aws_vpc.eks_vpc.id
  name   = "eks-node-sg"

  ingress {
    from_port   = 30000
    to_port     = 32767
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

resource "aws_launch_template" "node_lt" {
  name_prefix   = "eks-node-"
  image_id      = data.aws_ssm_parameter.eks_ami.value
  instance_type = "t3.micro"
  iam_instance_profile {
    name = aws_iam_instance_profile.node_profile.name
  }
  vpc_security_group_ids = [aws_security_group.node_sg.id]
  user_data = base64encode("#!/bin/bash\n/etc/eks/bootstrap.sh demo-eks-cluster")
}

resource "aws_autoscaling_group" "nodes" {
  desired_capacity     = 2
  max_size             = 2
  min_size             = 2
  vpc_zone_identifier  = [for s in aws_subnet.eks_subnet : s.id]

  launch_template {
    id      = aws_launch_template.node_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "kubernetes.io/cluster/demo-eks-cluster"
    value               = "owned"
    propagate_at_launch = true
  }
}
