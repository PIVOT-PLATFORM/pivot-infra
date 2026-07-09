variable "project_id" {
  description = "GCP project ID."
  type        = string
  default     = "pivot-project-501905"
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone (must be in region)."
  type        = string
  default     = "europe-west1-b"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "ssh_user" {
  description = "SSH user — must match PROD_SSH_USER in pivot-core's GitHub Actions secrets (EN07.5)."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key contents (e.g. via file(\"~/.ssh/pivot_mvp.pub\") in terraform.tfvars)."
  type        = string
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed on port 22 — your IP/32, never 0.0.0.0/0."
  type        = list(string)
}
