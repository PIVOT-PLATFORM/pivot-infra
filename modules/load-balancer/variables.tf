variable "project_id" { type = string }
variable "region" { type = string }

variable "name" {
  type        = string
  default     = "pivot-lb"
  description = "Name prefix for LB resources."
}

variable "ssl_domains" {
  type        = list(string)
  description = "Domains for the Google-managed cert (e.g. [\"recette.pivot.example\"])."
}

variable "spa_bucket_name" {
  type        = string
  description = "Globally-unique GCS bucket name for the Angular SPA."
}

variable "spa_public" {
  type        = bool
  default     = true
  description = "Grant allUsers objectViewer on the SPA bucket (public static site behind CDN)."
}

variable "services" {
  description = <<-EOT
    Cloud Run backends. Key = logical id used in path_rules.
      - service_name:     Cloud Run service name (cloud-run-service output).
      - timeout_sec:      backend timeout. 3600 for the WebSocket service.
      - session_affinity: true for the WebSocket service.
  EOT
  type = map(object({
    service_name     = string
    timeout_sec      = number
    session_affinity = bool
  }))
}

variable "path_rules" {
  description = <<-EOT
    Ordered URL-map path rules (nginx location parity). Longest-prefix wins is
    handled by GCP. Example:
      [
        { paths = ["/api/collaboratif/*", "/ws/collaboratif/*"], service_key = "collaboratif" },
        { paths = ["/api/*"],                                     service_key = "core" },
      ]
    Everything else falls through to the SPA bucket (default_service).
  EOT
  type = list(object({
    paths       = list(string)
    service_key = string
  }))
}
