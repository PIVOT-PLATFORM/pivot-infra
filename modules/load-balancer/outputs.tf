output "ip_address" {
  value       = google_compute_global_address.lb.address
  description = "LB anycast IP — point the DNS A record here (dns module)."
}

output "spa_bucket" {
  value       = google_storage_bucket.spa.name
  description = "SPA bucket — pivot-ui CI uploads dist/ here, then invalidates the CDN."
}

output "managed_cert_name" {
  value       = google_compute_managed_ssl_certificate.this.name
  description = "Managed cert name — gcloud compute ssl-certificates describe to watch it reach ACTIVE."
}
