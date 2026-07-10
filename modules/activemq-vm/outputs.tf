output "internal_ip" {
  value       = google_compute_instance.this.network_interface[0].network_ip
  description = "Private IP — collaboratif-core PIVOT_ACTIVEMQ_RELAY_HOST."
}

output "stomp_port" {
  value       = var.stomp_port
  description = "STOMP port — PIVOT_ACTIVEMQ_RELAY_PORT."
}

output "instance_name" {
  value       = google_compute_instance.this.name
  description = "VM name (for gcloud compute ssh --tunnel-through-iap)."
}

output "redis_host" {
  value       = google_compute_instance.this.network_interface[0].network_ip
  description = "Private IP for the co-located Redis (when run_redis=true) — SPRING_DATA_REDIS_HOST in dev."
}

output "redis_port" {
  value       = var.redis_port
  description = "Co-located Redis port."
}
