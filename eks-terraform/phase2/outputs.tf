###############################################################################
# phase2/outputs.tf
###############################################################################

output "alb_controller_status" {
  value = "ALB controller deployed: ${helm_release.alb_controller.name} v${helm_release.alb_controller.version}"
}

output "kubectl_configured" {
  value      = "kubectl configured on instance ${local.kubectl_instance_id} via SSM"
  depends_on = [null_resource.configure_kubectl]
}

output "next_steps" {
  value = <<-EOT
    Deployment complete! Connect to kubectl instance:
      aws ssm start-session --target ${local.kubectl_instance_id} --region ${var.aws_region}

    Then run:
      kubectl get nodes
      kubectl get pods -A
  EOT
}
