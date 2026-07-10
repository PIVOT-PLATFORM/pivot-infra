terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Workload Identity Federation for GitHub Actions ------------------------
# Keyless CI → GCP. Replaces every long-lived credential the current pipeline
# relies on: PROD_SSH_HOST/USER/KEY/PORT (SSH deploy) and GH_PACKAGES_TOKEN
# (GHCR login). GitHub Actions presents its OIDC token; GCP exchanges it for a
# short-lived access token that impersonates a per-repo deployer SA.
#
# Trust is pinned to the org (attribute_condition below): only repositories
# owned by var.github_owner can exchange a token at all. Each deployer SA can
# then only be impersonated by ITS repo (principalSet binding per deployer).

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Keyless OIDC federation for ${var.github_owner} GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"

  # Org-wide guardrail: tokens from any repo NOT owned by github_owner are
  # rejected at exchange time, before any SA impersonation is even considered.
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  # `environment` is deliberately NOT mapped: GitHub only includes that claim
  # for jobs that declare a `environment:`, so mapping it would break token
  # exchange for jobs that don't (e.g. the Artifact Registry push in
  # release.yml). Prod is gated by the GitHub Environment approval in the
  # workflow itself, not by this mapping.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- Deployer service accounts (one per repo) --------------------------------
# Each service repo impersonates its own deployer SA. Least privilege: a
# service's CI gets artifactregistry.writer (push its image) and nothing more;
# only the orchestrator (pivot-infra) gets run.admin to actually deploy.

resource "google_service_account" "deployer" {
  for_each = var.deployers

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = "CI deployer — ${each.key}"
}

# Project-level roles per deployer (e.g. artifactregistry.writer for service
# repos; run.admin for the orchestrator). serviceAccountUser on the runtime
# SAs is granted in the environment (where the runtime SAs exist) using the
# `deployer_emails` output — scoped per-SA rather than project-wide.
resource "google_project_iam_member" "deployer_roles" {
  for_each = local.deployer_role_pairs

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.deployer[each.value.deployer].email}"
}

# Bind the GitHub repo (via WIF principalSet) to its deployer SA so Actions in
# that repo — and only that repo — can impersonate it. An explicit
# `wif_principal` override allows tightening to a branch/tag/environment.
resource "google_service_account_iam_member" "wif_impersonation" {
  for_each = var.deployers

  service_account_id = google_service_account.deployer[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member = coalesce(
    each.value.wif_principal,
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${each.key}"
  )
}

locals {
  # Flatten deployers × their roles into one keyed map for for_each.
  deployer_role_pairs = merge([
    for name, cfg in var.deployers : {
      for role in cfg.project_roles :
      "${name}:${role}" => { deployer = name, role = role }
    }
  ]...)
}
