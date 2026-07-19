variable "project_id" {
  type        = string
  default     = "pivot-project-501905"
  description = "GCP project. recette-managed stays in the existing project during transition (prod may move to a dedicated project — see plan decision #1)."
}

variable "region" {
  type        = string
  default     = "europe-west1"
  description = "Region for all managed resources."
}

variable "project_number" {
  type        = string
  default     = "25190701001"
  description = "GCP project number — used to build the edge's deterministic Cloud Run URL when edge_host is unset."
}

variable "edge_host" {
  type        = string
  default     = ""
  description = "Real edge (pivot-ui) run.app hostname (no scheme), used for backends' PIVOT_APP_URL/CORS. Empty = fall back to the deterministic pattern (pre-first-apply). Set to the actual URL once known (this project uses legacy hash URLs, not deterministic)."
}

variable "github_owner" {
  type        = string
  default     = "PIVOT-PLATFORM"
  description = "GitHub org allowed to federate via WIF."
}

variable "subnet_cidr" {
  type        = string
  default     = "10.20.0.0/24"
  description = "Primary subnet for the managed stack. Distinct from the live VM VPC (10.10.0.0/24) so both can coexist during transition."
}

variable "zone" {
  type        = string
  default     = "europe-west1-b"
  description = "Zone for the ActiveMQ VM + its persistent disk."
}

# --- Images (set to the digests emitted by each service's release.yml) -------
variable "pivot_core_image" {
  type        = string
  default     = "europe-west1-docker.pkg.dev/pivot-project-501905/pivot/pivot-core:PLACEHOLDER"
  description = "pivot-core image, ideally by @sha256 digest. Placeholder until Phase 1 pushes to Artifact Registry."
}

# EN53 (ADR-030) — variables pivot_collaboratif_image / pivot_agilite_image retirées :
# agilité et collaboratif sont des modules internes de l'image pivot-core (modulith).

variable "pivot_ui_image" {
  type        = string
  default     = "europe-west1-docker.pkg.dev/pivot-project-501905/pivot/pivot-ui:PLACEHOLDER"
  description = "pivot-ui edge (nginx + SPA) image, ideally by @sha256 digest."
}

# --- SMTP (public egress; not secret except the password) --------------------
variable "smtp_host" {
  type        = string
  default     = ""
  description = "SMTP relay host (SPRING_MAIL_HOST)."
}

variable "smtp_port" {
  type        = number
  default     = 587
  description = "SMTP relay port."
}

variable "smtp_username" {
  type        = string
  default     = ""
  description = "SMTP username (password comes from the mail-password secret)."
}

variable "mail_from" {
  type        = string
  default     = ""
  description = "PIVOT_MAIL_FROM address."
}

# --- FinOps: Cloud SQL stop/start schedule -----------------------------------
variable "sql_schedule_tz" {
  type        = string
  default     = "Europe/Paris"
  description = "Time zone for the Cloud SQL stop/start scheduler jobs."
}

variable "sql_stop_cron" {
  type        = string
  default     = "0 22 * * *"
  description = "Cron to STOP Cloud SQL (unix cron, in sql_schedule_tz). Default 22:00 daily."
}

variable "sql_start_cron" {
  type        = string
  default     = "0 7 * * *"
  description = "Cron to START Cloud SQL. Default 07:00 daily."
}
