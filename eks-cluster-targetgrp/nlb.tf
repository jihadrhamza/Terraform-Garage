resource "aws_lb" "nlb" {
  name               = "eks-nlb"
  load_balancer_type = "network"
  subnets            = [for s in aws_subnet.eks_subnet : s.id]
}

resource "aws_lb_target_group" "nginx_tg" {
  name     = "nginx-tg"
  port     = 30080
  protocol = "TCP"
  vpc_id   = aws_vpc.eks_vpc.id
}

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_tg.arn
  }
}

# Make sure you have aws_vpc.eks_vpc and aws_subnet.eks_subnet resources defined in your configuration.
