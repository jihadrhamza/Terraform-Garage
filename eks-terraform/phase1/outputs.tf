###############################################################################
# phase1/outputs.tf
# All outputs are read by phase2 and phase3 via terraform_remote_state.
###############################################################################

output "vpc_id"              { value = module.vpc.vpc_id }
output "public_subnet_ids"  { value = module.vpc.public_subnet_ids }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }

output "cluster_name"      { value = module.eks.cluster_name }
output "cluster_endpoint"  { value = module.eks.cluster_endpoint }
output "cluster_ca"        { value = module.eks.cluster_ca }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "oidc_provider_url" { value = module.eks.oidc_provider_url }
output "node_role_arn"     { value = module.eks.node_role_arn }

output "kubectl_instance_id"  { value = module.kubectl_instance.instance_id }
output "kubectl_iam_role_arn" { value = module.kubectl_instance.iam_role_arn }

output "alb_sg_id"               { value = module.alb.alb_sg_id }
output "alb_controller_role_arn" { value = module.alb.alb_controller_role_arn }

output "acm_certificate_arn" {
  value       = module.acm.certificate_arn
  description = "ARN of the imported self-signed ACM certificate"
}

output "kubectl_ssm_command" {
  value = "aws ssm start-session --target ${module.kubectl_instance.instance_id} --region ${var.aws_region}"
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
