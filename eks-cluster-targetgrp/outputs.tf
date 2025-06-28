output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "nlb_dns_name" {
  value = aws_lb.nlb.dns_name
}
