output "repository_id" {
  value       = google_artifact_registry_repository.docker.repository_id
  description = "The Artifact Registry repository ID."
}

output "repository_name" {
  value       = google_artifact_registry_repository.docker.name
  description = "Full resource name of the repository."
}

output "registry_host" {
  value       = "${var.region}-docker.pkg.dev"
  description = "Docker registry host to `docker login` / tag against."
}

output "image_prefix" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
  description = "Prefix for image references: <image_prefix>/<service>@sha256:<digest>."
}
