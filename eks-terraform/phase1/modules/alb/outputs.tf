###############################################################################
# modules/alb/outputs.tf
# ALB itself is owned by the controller — only SG and IRSA outputs remain.
###############################################################################

output "alb_sg_id" {
  value       = aws_security_group.alb.id
  description = "Security group ID to pass to the ALB controller via Ingress annotation"
}

output "alb_controller_role_arn" {
  value       = aws_iam_role.alb_controller.arn
  description = "IRSA role ARN for the AWS Load Balancer Controller"
}
