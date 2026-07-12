output "secret_ids" {
  value       = { for id, s in google_secret_manager_secret.this : id => s.secret_id }
  description = "Map of logical name -> Secret Manager secret_id, for the Cloud Run module to reference in secret volume mounts."
}
