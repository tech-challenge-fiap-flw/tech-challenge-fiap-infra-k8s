variable "environment" {
  description = "Ambiente de deploy (prod, staging, dev)"
  type        = string
  default     = "staging"
}

variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}
