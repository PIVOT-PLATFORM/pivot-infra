output "external_ip" {
  description = "Static external IP — use as PROD_SSH_HOST (EN07.5) and for any DNS A record."
  value       = google_compute_address.this.address
}

output "instance_name" {
  value = google_compute_instance.this.name
}

output "service_account_email" {
  value = google_service_account.vm.email
}
