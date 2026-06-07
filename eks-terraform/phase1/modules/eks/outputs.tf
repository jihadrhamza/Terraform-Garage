###############################################################################
# modules/eks/outputs.tf
###############################################################################

output "cluster_name"      { value = aws_eks_cluster.main.name }
output "cluster_endpoint"  { value = aws_eks_cluster.main.endpoint }
output "cluster_ca"        { value = aws_eks_cluster.main.certificate_authority[0].data }
output "cluster_role_arn"  { value = aws_iam_role.cluster.arn }
output "node_role_arn"     { value = aws_iam_role.node.arn }
output "node_sg_id"        { value = aws_security_group.nodes.id }

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  value = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
