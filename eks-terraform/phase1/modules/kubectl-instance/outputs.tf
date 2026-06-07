###############################################################################
# modules/kubectl-instance/outputs.tf
###############################################################################

output "instance_id"        { value = aws_instance.kubectl.id }
output "instance_public_ip" { value = aws_instance.kubectl.public_ip }
output "iam_role_arn"       { value = aws_iam_role.kubectl.arn }
