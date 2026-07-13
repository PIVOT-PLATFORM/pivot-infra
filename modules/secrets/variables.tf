variable "project_id" {
  type        = string
  description = "GCP project hosting the secrets."
}

variable "region" {
  type        = string
  description = "Region for user-managed replication (data residency: europe-west1)."
}

variable "secrets" {
  description = <<-EOT
    Map of secret_id -> { accessors }. Values are added out of band.
    Example:
      {
        "postgres-password" = { accessors = ["serviceAccount:sa-pivot-core@<proj>.iam.gserviceaccount.com"] }
        "mail-password"     = { accessors = ["serviceAccount:sa-pivot-core@<proj>.iam.gserviceaccount.com"] }
        "otp-secret"        = { accessors = ["serviceAccount:sa-pivot-core@<proj>.iam.gserviceaccount.com"] }
        "redis-auth"        = { accessors = ["serviceAccount:sa-pivot-core@<proj>.iam.gserviceaccount.com",
                                             "serviceAccount:sa-pivot-collaboratif@<proj>.iam.gserviceaccount.com"] }
      }
  EOT
  type = map(object({
    accessors = list(string)
  }))
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to each secret."
}
