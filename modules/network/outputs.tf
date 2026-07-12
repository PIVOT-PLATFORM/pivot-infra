output "network_id" {
  value       = google_compute_network.this.id
  description = "VPC self-link/id — pass to the connector, Cloud SQL private IP, Memorystore, and the ActiveMQ VM."
}

output "network_name" {
  value       = google_compute_network.this.name
  description = "VPC name."
}

output "subnet_id" {
  value       = google_compute_subnetwork.this.id
  description = "Primary subnet id."
}

output "subnet_cidr" {
  value       = google_compute_subnetwork.this.ip_cidr_range
  description = "Primary subnet range."
}

output "psa_connection" {
  value       = google_service_networking_connection.psa.id
  description = "PSA connection id — depend on this before creating Cloud SQL/Memorystore private-IP instances."
}
