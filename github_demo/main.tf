terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  token = var.token # or `GITHUB_TOKEN`
}

resource "github_repository" "terraform_garage" {
  name        = "Test-Garage"
  description = "Test sample codebase"

  visibility = "public"

}