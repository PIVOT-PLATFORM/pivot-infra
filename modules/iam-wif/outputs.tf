output "pool_name" {
  value       = google_iam_workload_identity_pool.github.name
  description = "Full resource name of the WIF pool."
}

output "provider_name" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Full resource name of the WIF provider — pass as `workload_identity_provider` to google-github-actions/auth."
}

output "deployer_emails" {
  value       = { for name, sa in google_service_account.deployer : name => sa.email }
  description = "Map repo -> deployer SA email. Use as `service_account` in google-github-actions/auth, and to bind iam.serviceAccountUser on runtime SAs in the environment."
}
