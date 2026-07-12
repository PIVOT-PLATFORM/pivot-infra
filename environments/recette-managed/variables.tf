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

variable "pivot_collaboratif_image" {
  type        = string
  default     = "europe-west1-docker.pkg.dev/pivot-project-501905/pivot/pivot-collaboratif-core:PLACEHOLDER"
  description = "pivot-collaboratif-core image, ideally by @sha256 digest."
}

# --- Edge / hostnames --------------------------------------------------------
variable "recette_host" {
  type        = string
  default     = "recette.pivot.example"
  description = "Public hostname for the recette-managed stack (managed cert domain + A record). Set to the real domain."
}

variable "spa_bucket_name" {
  type        = string
  default     = "pivot-recette-spa-501905"
  description = "Globally-unique GCS bucket name for the Angular SPA."
}

variable "manage_dns_zone" {
  type        = bool
  default     = false
  description = "Create the Cloud DNS zone here (true) or reuse an existing one (false)."
}

variable "dns_zone_name" {
  type        = string
  default     = "pivot-zone"
  description = "Cloud DNS managed zone resource name."
}

variable "dns_zone_dns_name" {
  type        = string
  default     = "pivot.example."
  description = "Zone DNS name with trailing dot (required when manage_dns_zone=true)."
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
