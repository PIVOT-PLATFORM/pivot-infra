output "host" {
  value       = google_redis_instance.this.host
  description = "Private IP — SPRING_DATA_REDIS_HOST."
}

output "port" {
  value       = google_redis_instance.this.port
  description = "Redis port — SPRING_DATA_REDIS_PORT (default 6379)."
}

output "auth_string" {
  value       = google_redis_instance.this.auth_string
  sensitive   = true
  description = "AUTH password. Push into the `redis-auth` Secret Manager secret; do not surface in logs."
}

output "server_ca_cert" {
  value       = try(google_redis_instance.this.server_ca_certs[0].cert, null)
  sensitive   = true
  description = "Server CA cert for in-transit TLS (SERVER_AUTHENTICATION) — clients validate against it."
}
