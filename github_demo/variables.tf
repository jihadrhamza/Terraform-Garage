variable "token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "owner" {
  description = "GitHub username or organization name"
  type        = string
  default     = ""
}