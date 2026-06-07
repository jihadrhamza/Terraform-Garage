###############################################################################
# modules/alb/providers.tf
###############################################################################

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
