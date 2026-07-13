terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Secret Manager (replaces ansible-vault) --------------------------------
# Creates the secret CONTAINERS only. Values are added out of band (never in
# Terraform state):
#   echo -n "<value>" | gcloud secrets versions add <id> --data-file=-
#
# Cloud Run mounts each secret as a FILE (see modules/cloud-run-service). The
# mount path/filename — not the Secret Manager id — must equal the Spring
# configtree key, e.g. mounted at /run/secrets/secret.datasource-password so
# pivot-core's application-prod.yml (SECRET_FILE_PATH=/run/secrets) reads it
# unchanged. That mapping lives in the Cloud Run module; here we just provision
# the secrets and grant read access to the runtime SAs that consume them.

resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = var.labels
}

# Grant secretAccessor per secret to exactly the runtime SAs that need it —
# scoped, never project-wide (least privilege).
resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = local.accessor_pairs

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}

locals {
  accessor_pairs = merge([
    for id, cfg in var.secrets : {
      for member in cfg.accessors :
      "${id}:${member}" => { secret = id, member = member }
    }
  ]...)
}
