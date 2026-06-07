###############################################################################
# modules/acm/main.tf
# Imports a self-signed (or private-CA) certificate into ACM so the ALB
# listener can terminate HTTPS.  The cert files live in phase1/certs/.
###############################################################################

resource "aws_acm_certificate" "imported" {
  private_key       = file(var.private_key_path)
  certificate_body  = file(var.certificate_body_path)
  certificate_chain = file(var.certificate_chain_path)

  tags = {
    Name = var.domain_name
  }

  lifecycle {
    create_before_destroy = true
  }
}
