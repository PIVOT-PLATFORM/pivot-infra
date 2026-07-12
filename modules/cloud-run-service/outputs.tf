output "service_name" {
  value       = google_cloud_run_v2_service.this.name
  description = "Cloud Run service name."
}

output "uri" {
  value       = google_cloud_run_v2_service.this.uri
  description = "Service URI (internal — reached via the LB, not publicly)."
}

output "location" {
  value       = google_cloud_run_v2_service.this.location
  description = "Region — used when building the Serverless NEG in the load-balancer module."
}
