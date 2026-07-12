output "private_ip" {
  value       = google_sql_database_instance.this.private_ip_address
  description = "Private IP — SPRING_DATASOURCE_URL = jdbc:postgresql://<private_ip>:5432/pivot."
}

output "connection_name" {
  value       = google_sql_database_instance.this.connection_name
  description = "Instance connection name (project:region:instance) for the Cloud SQL connector / gcloud sql connect."
}

output "instance_name" {
  value       = google_sql_database_instance.this.name
  description = "Instance name."
}

output "database_name" {
  value       = google_sql_database.pivot.name
  description = "Application database name."
}
