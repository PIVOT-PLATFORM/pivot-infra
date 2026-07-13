output "service_name" {
  value       = google_cloud_run_v2_service.this.name
  description = "Cloud Run service name."
}

output "uri" {
  value       = google_cloud_run_v2_service.this.uri
  description = "Service URI (https://…). Public when ingress=ALL, else LB-only."
}

output "uri_host" {
  value       = replace(google_cloud_run_v2_service.this.uri, "https://", "")
  description = "Service hostname without scheme — used as an nginx upstream (proxy_pass https://$host + Host header)."
}

output "location" {
  value       = google_cloud_run_v2_service.this.location
  description = "Region — used when building the Serverless NEG in the load-balancer module."
}
