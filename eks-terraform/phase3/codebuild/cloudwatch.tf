###############################################################################
# phase3/codebuild/cloudwatch.tf
###############################################################################

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "/aws/codebuild/${local.name_prefix}"
  })
}
