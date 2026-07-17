# Values CI and operators consume.

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
  description = "VPC name (backend Cloud Run uses Direct VPC egress into its subnet — no connector)."
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

# --- Service URLs ------------------------------------------------------------

output "edge_url" {
  value       = module.run_edge.uri
  description = "PUBLIC entry point — open this in a browser. The pivot-ui edge (SPA + /api reverse proxy)."
}

output "service_urls" {
  value = {
    "pivot-ui"                = module.run_edge.uri
    "pivot-core"              = module.run_core.uri
    "pivot-collaboratif-core" = module.run_collaboratif.uri
    "pivot-agilite-core"      = module.run_agilite.uri
  }
  description = "All Cloud Run service URLs. Backends are reached by the edge; set vars.RECETTE_BASE_URL (orchestrator) to edge_url."
}
