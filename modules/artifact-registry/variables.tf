variable "project_id" {
  type        = string
  description = "GCP project hosting the Artifact Registry repository."
}

variable "region" {
  type        = string
  description = "Region for the Docker repository (e.g. europe-west1)."
}

variable "repository_id" {
  type        = string
  default     = "pivot"
  description = "Repository ID. Images live at <region>-docker.pkg.dev/<project>/<repository_id>/<service>."
}

variable "reader_members" {
  type        = list(string)
  default     = []
  description = "IAM members granted artifactregistry.reader (Cloud Run runtime SAs), e.g. [\"serviceAccount:sa-pivot-core@<project>.iam.gserviceaccount.com\"]."
}

variable "untagged_ttl" {
  type        = string
  default     = "2592000s" # 30 days
  description = "Age after which UNTAGGED images are deleted by the cleanup policy."
}

variable "cleanup_dry_run" {
  type        = bool
  default     = true
  description = "When true, cleanup policies only log what they would delete. Flip to false once validated in recette."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to the repository."
}
