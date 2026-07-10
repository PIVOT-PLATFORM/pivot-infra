# Values CI and later phases consume.

output "wif_provider_name" {
  value       = module.iam_wif.provider_name
  description = "Set as `workload_identity_provider` in google-github-actions/auth across all service repos."
}

output "deployer_emails" {
  value       = module.iam_wif.deployer_emails
  description = "Per-repo deployer SA emails — `service_account` for google-github-actions/auth."
}

output "image_prefix" {
  value       = module.artifact_registry.image_prefix
  description = "Tag/push service images as <image_prefix>/<service>@sha256:<digest>."
}

output "registry_host" {
  value       = module.artifact_registry.registry_host
  description = "Artifact Registry host for docker login / gcloud auth configure-docker."
}

output "network_name" {
  value       = module.network.network_name
  description = "VPC name (Cloud Run uses Direct VPC egress into its subnet — no connector)."
}

output "dev_redis_host" {
  value       = module.activemq.redis_host
  description = "Co-located dev Redis private IP (BUILD cost posture; prod uses Memorystore)."
}

output "runtime_sa_emails" {
  value       = { for k, sa in google_service_account.runtime : k => sa.email }
  description = "Runtime SA emails attached to the Cloud Run services."
}

output "cloud_sql_private_ip" {
  value       = module.cloud_sql.private_ip
  description = "Cloud SQL private IP (SPRING_DATASOURCE_URL host)."
}

output "cloud_sql_connection_name" {
  value       = module.cloud_sql.connection_name
  description = "Cloud SQL connection name (gcloud sql connect / DMS cutover)."
}

output "lb_ip_address" {
  value       = module.lb.ip_address
  description = "LB anycast IP — point the recette DNS A record here (already wired via the dns module)."
}

output "spa_bucket" {
  value       = module.lb.spa_bucket
  description = "SPA bucket — pivot-ui CI uploads dist/ here."
}

output "dns_name_servers" {
  value       = module.dns.name_servers
  description = "Delegate the domain to these NS (only when manage_dns_zone=true)."
}
