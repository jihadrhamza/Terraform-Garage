###############################################################################
# phase3/codebuild/security_group.tf
###############################################################################

resource "aws_security_group" "codebuild" {
  name        = "${local.name_prefix}-codebuild-sg"
  description = "CodeBuild runner agent - controls egress from the build environment"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-codebuild-sg"
  })
}
