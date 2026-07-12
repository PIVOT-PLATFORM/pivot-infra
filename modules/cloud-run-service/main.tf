terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Reusable Cloud Run service ---------------------------------------------
# One instance of this module per backend service (pivot-core,
# pivot-collaboratif-core, later pilotage/agilite). Deployed by IMAGE DIGEST
# (immutable) — the digest validated in recette is the exact artifact promoted
# to prod.
#
# Ingress is internal + load balancer only: the raw run.app URL is never
# reachable, only the external HTTPS LB (and internal VPC callers). Egress goes
# through the Serverless VPC connector, PRIVATE_RANGES_ONLY, so Cloud SQL /
# Redis / ActiveMQ private IPs are reachable while public egress (SMTP, OIDC)
# keeps the normal path.

resource "google_cloud_run_v2_service" "this" {
  project             = var.project_id
  name                = var.name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.deletion_protection

  template {
    service_account                  = var.service_account_email
    timeout                          = "${var.timeout_seconds}s"
    max_instance_request_concurrency = var.concurrency
    session_affinity                 = var.session_affinity

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Direct VPC egress (no always-on Serverless VPC connector to pay for).
    # Cloud Run instances get an IP from the subnet and reach Cloud SQL/Redis/
    # ActiveMQ private IPs directly. PRIVATE_RANGES_ONLY keeps public egress
    # (SMTP, OIDC) on the normal path.
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnetwork_id
      }
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # Plain (non-secret) environment.
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret-backed environment (Secret Manager -> env var).
      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.value.name
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = try(env.value.version, "latest")
            }
          }
        }
      }

      # Secret files (Spring configtree /run/secrets contract). Each entry is
      # one Secret Manager secret mounted at its own mount_path. NOTE: Cloud Run
      # requires distinct mount_paths per volume, so preserving the exact
      # single-dir /run/secrets/<key> layout for MULTIPLE secrets needs either
      # an entrypoint shim or relaxed-binding env vars — see module README.
      dynamic "volume_mounts" {
        for_each = var.secret_volumes
        content {
          name       = volume_mounts.value.name
          mount_path = volume_mounts.value.mount_path
        }
      }

      startup_probe {
        initial_delay_seconds = var.startup_initial_delay
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = var.startup_failure_threshold
        http_get {
          path = var.startup_probe_path
          port = var.probe_port
        }
      }

      liveness_probe {
        timeout_seconds = 5
        period_seconds  = 30
        http_get {
          path = var.liveness_probe_path
          port = var.probe_port
        }
      }
    }

    dynamic "volumes" {
      for_each = var.secret_volumes
      content {
        name = volumes.value.name
        secret {
          secret = volumes.value.secret
          items {
            path    = volumes.value.file_name
            version = try(volumes.value.version, "latest")
          }
        }
      }
    }
  }
}

# Who may invoke the service. For the LB-fronted services this is the LB /
# gateway identity, not allUsers (ingress already blocks the public run.app URL,
# but invoker IAM is the second layer).
resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.invokers)

  project  = google_cloud_run_v2_service.this.project
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
