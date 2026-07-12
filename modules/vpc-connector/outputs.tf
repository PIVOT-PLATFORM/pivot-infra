output "connector_id" {
  value       = google_vpc_access_connector.this.id
  description = "Connector id — set as the Cloud Run service `vpc_access.connector`."
}

output "connector_cidr" {
  value       = google_vpc_access_connector.this.ip_cidr_range
  description = "Connector /28 — add to the network module's internal_ingress_ranges so it can reach the data tier."
}
