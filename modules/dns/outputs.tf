output "name_servers" {
  value       = var.manage_zone ? google_dns_managed_zone.this[0].name_servers : []
  description = "Delegate the domain to these NS at your registrar (when the zone is managed here)."
}

output "zone_name" {
  value       = local.zone_name
  description = "Managed zone name."
}
