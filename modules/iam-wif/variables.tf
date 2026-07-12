variable "project_id" {
  type        = string
  description = "GCP project hosting the WIF pool and deployer SAs."
}

variable "github_owner" {
  type        = string
  default     = "PIVOT-PLATFORM"
  description = "GitHub org that owns the repos allowed to federate. Enforced as an org-wide attribute condition on the provider."
}

variable "pool_id" {
  type        = string
  default     = "github-actions"
  description = "Workload Identity Pool ID."
}

variable "provider_id" {
  type        = string
  default     = "github-oidc"
  description = "Workload Identity Pool Provider ID."
}

variable "deployers" {
  description = <<-EOT
    Per-repo deployer service accounts. Key = GitHub repo name (e.g. "pivot-core").
      - account_id:     SA account_id (<= 30 chars, e.g. "dep-pivot-core").
      - project_roles:  project-level roles granted to the SA (least privilege).
                        Service repos: ["roles/artifactregistry.writer"].
                        Orchestrator (pivot-infra): ["roles/run.admin", "roles/artifactregistry.writer"].
      - wif_principal:  optional override to tighten which repo/branch/tag/env
                        may impersonate. Defaults to the whole repo.
  EOT
  type = map(object({
    account_id    = string
    project_roles = list(string)
    wif_principal = optional(string)
  }))
}
