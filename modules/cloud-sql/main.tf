terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Cloud SQL for PostgreSQL 18 --------------------------------------------
# Replaces the postgres container on the VM boot disk. Private IP only (no
# public IP), automated backups + point-in-time recovery — this is the core
# "data persistence" hardening goal: data no longer dies with the VM.
#
# Keeps the SINGLE `pivot` database with its 3 schemas (public/agilite/
# collaboratif). Schema ownership is driven by each service's Flyway at
# startup, unchanged — so no schema is declared here beyond the database itself.
#
# pgbouncer is retired: size max_connections vs (max Cloud Run instances ×
# Hikari pool). Managed connection pooling (Cloud SQL's built-in PgBouncer,
# session mode) can be enabled once on the provisioned instance — see NOTE
# below; kept out of Terraform here to stay schema-compatible with provider 6.x.

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = "POSTGRES_18"
  deletion_protection = var.deletion_protection

  # Private IP requires the PSA peering to exist first (network module).
  depends_on = [var.psa_connection]

  settings {
    tier              = var.tier
    availability_type = var.availability_type # ZONAL (recette) | REGIONAL (prod HA)
    disk_autoresize   = true
    disk_type         = "PD_SSD"
    edition           = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.retained_backups
      }
    }

    # Bound the pool ceiling explicitly (was pgbouncer's job). Sized to the
    # worst-case sum of Hikari pools across max Cloud Run instances.
    database_flags {
      name  = "max_connections"
      value = tostring(var.max_connections)
    }

    maintenance_window {
      day  = 7 # Sunday
      hour = 3
    }
  }
}

# The single application database. 3 schemas inside (public/agilite/
# collaboratif) are owned/migrated by the services' Flyway, not declared here.
resource "google_sql_database" "pivot" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

# NOTE — managed connection pooling (session mode) and the `pivot` SQL user are
# provisioned OUT OF BAND to keep the password out of Terraform state (source
# of truth = the `postgres-password` Secret Manager secret):
#
#   PW=$(gcloud secrets versions access latest --secret=postgres-password)
#   gcloud sql users create pivot --instance=<instance_name> --password="$PW"
#   # enable managed pooling (session mode) when available in your provider/console.
