terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Dedicated state prefix so the managed stack is built ALONGSIDE the live VM
  # (environments/recette, prefix "mvp-test") without touching its state.
  #
  # Partial config — bucket supplied at init:
  #   terraform init -backend-config="bucket=pivot-project-501905-tfstate"
  backend "gcs" {
    prefix = "recette-managed"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# managed-min — ultra-cheap Cloud Run stack, NO Load Balancer.
#
# FinOps posture (see pivot-docs plan "Déploiement automatique FinOps"):
#   - 5 Cloud Run services, all scale-to-zero, served DIRECTLY on their public
#     *.run.app URLs (ingress = ALL). The pivot-ui edge (nginx) is the single
#     public entry point and reverse-proxies /api/* to the backend run.app URLs.
#   - No HTTPS Load Balancer (~$18/mo saved), no SPA bucket/CDN, no Cloud DNS.
#   - No Memorystore, no ActiveMQ broker: collaboratif uses its in-memory
#     SimpleBroker (the additive ActiveMQ relay stays disabled). Redis IS needed
#     (rate limiting + whiteboard presence) so ONE tiny e2-micro VM hosts Redis
#     only (run_activemq=false) — far cheaper than Memorystore.
#   - Always-on cost = Cloud SQL db-f1-micro (stoppable) + the e2-micro Redis VM.
#
# Security: backends are public but protected by the app's opaque-token auth
# (duplicated per service). Tighten later to ingress=internal + IAM if wanted.
# =============================================================================

# --- Runtime service accounts (one identity per Cloud Run service) -----------
# Least privilege. All are granted Artifact Registry reader (image pull) by the
# artifact-registry module below; the data-tier accessors are scoped per secret.
resource "google_service_account" "runtime" {
  for_each = toset(["pivot-core", "pivot-collaboratif", "pivot-agilite", "pivot-pilotage", "pivot-ui"])

  project      = var.project_id
  account_id   = "sa-${each.value}"
  display_name = "Cloud Run runtime — ${each.value}"
}

# --- Foundation --------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  region     = var.region
  name       = "pivot-recette"

  # Direct VPC egress puts backend Cloud Run instances in this subnet, so the
  # subnet range is the source that must reach the data tier (Cloud SQL).
  internal_ingress_ranges = [var.subnet_cidr]
  subnet_cidr             = var.subnet_cidr
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = var.project_id
  region     = var.region

  # Every runtime SA pulls images; deployer SAs (iam-wif) push them.
  reader_members = [for sa in google_service_account.runtime : "serviceAccount:${sa.email}"]

  labels = local.labels
}

module "iam_wif" {
  source = "../../modules/iam-wif"

  project_id   = var.project_id
  github_owner = var.github_owner

  deployers = {
    "pivot-core"              = { account_id = "dep-pivot-core", project_roles = ["roles/artifactregistry.writer"] }
    "pivot-ui"                = { account_id = "dep-pivot-ui", project_roles = ["roles/artifactregistry.writer"] }
    "pivot-collaboratif-core" = { account_id = "dep-pivot-collab-core", project_roles = ["roles/artifactregistry.writer"] }
    "pivot-agilite-core"      = { account_id = "dep-pivot-agilite-core", project_roles = ["roles/artifactregistry.writer"] }
    "pivot-pilotage-core"     = { account_id = "dep-pivot-pilotage-core", project_roles = ["roles/artifactregistry.writer"] }
    # Orchestrator: deploys revisions to Cloud Run. serviceAccountUser on each
    # runtime SA is bound below (per-SA, not project-wide).
    "pivot-infra" = { account_id = "dep-orchestrator", project_roles = ["roles/run.admin", "roles/artifactregistry.writer"] }
  }
}

# The orchestrator SA must act-as each runtime SA to deploy a revision that runs
# as it. Scoped per-SA (not project-wide serviceAccountUser).
resource "google_service_account_iam_member" "orchestrator_actas_runtime" {
  for_each = google_service_account.runtime

  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.iam_wif.deployer_emails["pivot-infra"]}"
}

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.project_id
  region     = var.region

  # No redis-auth secret: the self-hosted Redis VM is VPC-internal, no AUTH.
  secrets = {
    "postgres-password" = { accessors = [for k in ["pivot-core", "pivot-collaboratif", "pivot-agilite", "pivot-pilotage"] : "serviceAccount:${google_service_account.runtime[k].email}"] }
    "mail-password"     = { accessors = ["serviceAccount:${google_service_account.runtime["pivot-core"].email}"] }
    "otp-secret"        = { accessors = ["serviceAccount:${google_service_account.runtime["pivot-core"].email}"] }
  }

  labels = local.labels
}

# --- Data tier ---------------------------------------------------------------

module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id     = var.project_id
  region         = var.region
  instance_name  = "pivot-recette-pg"
  network_id     = module.network.network_id
  psa_connection = module.network.psa_connection

  # FinOps: smallest shared-core tier, ZONAL, no HA. Stoppable when idle.
  tier                = "db-f1-micro"
  availability_type   = "ZONAL"
  deletion_protection = false
}

# Redis is REQUIRED (not just a cache): pivot-core rate limiting + collaboratif
# whiteboard presence/membership hard-depend on StringRedisTemplate. Cheapest
# option that actually works = one tiny always-on VM hosting only Redis (no
# Memorystore ~$35/mo, no LB). ActiveMQ is NOT run (run_activemq=false) — the
# in-memory SimpleBroker covers the whiteboard, so this VM is Redis-only.
# assign_public_ip=true lets it pull the redis image at boot (no Cloud NAT);
# inbound stays firewall-locked (private IP, VPC-internal only).
module "redis_vm" {
  source = "../../modules/activemq-vm"

  project_id       = var.project_id
  zone             = var.zone
  name             = "pivot-recette-redis"
  subnet_id        = module.network.subnet_id
  machine_type     = "e2-micro"
  run_activemq     = false
  run_redis        = true
  assign_public_ip = true

  labels = local.labels
}

# --- Application tier (Cloud Run) --------------------------------------------
# All backends: public run.app URL (ingress=ALL), scale-to-zero. Redis reached
# over Direct VPC egress (private IP). MANAGEMENT_SERVER_PORT = serving port so
# Cloud Run probes reach actuator.
locals {
  # Public URL of the edge (pivot-ui), used by backends for PIVOT_APP_URL (email
  # links) and CORS. Computed from Cloud Run's deterministic URL scheme
  # (https://<service>-<project_number>.<region>.run.app) to avoid a dependency
  # cycle with run_edge (which itself needs the backend URLs). Verify post-apply
  # with `gcloud run services describe pivot-ui`; if the project uses the legacy
  # random-hash URL, correct PIVOT_APP_URL/CORS with one `gcloud run update`.
  edge_host = var.edge_host != "" ? var.edge_host : "pivot-ui-${var.project_number}.${var.region}.run.app"

  # Redis wiring shared by every backend (self-hosted VM, VPC-internal, no TLS).
  redis_env = {
    SPRING_DATA_REDIS_HOST        = module.redis_vm.redis_host
    SPRING_DATA_REDIS_PORT        = tostring(module.redis_vm.redis_port)
    SPRING_DATA_REDIS_SSL_ENABLED = "false"
  }
}

module "run_core" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-core"
  image                 = var.pivot_core_image
  ingress               = "INGRESS_TRAFFIC_ALL"
  service_account_email = google_service_account.runtime["pivot-core"].email
  network_id            = module.network.network_id
  subnetwork_id         = module.network.subnet_id

  container_port      = 8080
  probe_port          = 8080
  startup_probe_path  = "/api/actuator/health/readiness"
  liveness_probe_path = "/api/actuator/health/liveness"
  min_instances       = 0
  max_instances       = 2
  invokers            = ["allUsers"] # reached by the edge over the public URL

  env = merge(local.redis_env, {
    SPRING_PROFILES_ACTIVE     = "prod"
    MANAGEMENT_SERVER_PORT     = "8080"
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://${module.cloud_sql.private_ip}:5432/pivot?sslmode=require"
    SPRING_DATASOURCE_USERNAME = "pivot"
    SPRING_MAIL_HOST           = var.smtp_host
    SPRING_MAIL_PORT           = tostring(var.smtp_port)
    SPRING_MAIL_USERNAME       = var.smtp_username
    PIVOT_MAIL_FROM            = var.mail_from
    PIVOT_APP_URL              = "https://${local.edge_host}"
    CORS_ALLOWED_ORIGINS       = "https://${local.edge_host}"
  })

  secret_env = [
    { name = "SPRING_DATASOURCE_PASSWORD", secret = "postgres-password" },
    { name = "SPRING_MAIL_PASSWORD", secret = "mail-password" },
    { name = "PIVOT_AUTH_OTP_SECRET", secret = "otp-secret" },
  ]

  depends_on = [module.secrets, module.cloud_sql, module.redis_vm]
}

module "run_collaboratif" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-collaboratif-core"
  image                 = var.pivot_collaboratif_image
  ingress               = "INGRESS_TRAFFIC_ALL"
  service_account_email = google_service_account.runtime["pivot-collaboratif"].email
  network_id            = module.network.network_id
  subnetwork_id         = module.network.subnet_id

  container_port      = 8083
  probe_port          = 8083
  startup_probe_path  = "/api/collaboratif/actuator/health/readiness"
  liveness_probe_path = "/api/collaboratif/actuator/health/liveness"

  # In-memory SimpleBroker requires a single instance: max=1. Sticky + long
  # timeout for the whiteboard WebSocket.
  min_instances    = 0
  max_instances    = 1
  timeout_seconds  = 3600
  session_affinity = true
  invokers         = ["allUsers"]

  env = merge(local.redis_env, {
    SPRING_PROFILES_ACTIVE       = "prod"
    MANAGEMENT_SERVER_PORT       = "8083"
    SPRING_DATASOURCE_URL        = "jdbc:postgresql://${module.cloud_sql.private_ip}:5432/pivot?sslmode=require"
    SPRING_DATASOURCE_USERNAME   = "pivot"
    SPRING_FLYWAY_SCHEMAS        = "collaboratif"
    PIVOT_ACTIVEMQ_RELAY_ENABLED = "false"
    # ActiveMQ relay stays OFF (in-memory broker only) — no PIVOT_ACTIVEMQ_RELAY_*.
    PIVOT_APP_URL        = "https://${local.edge_host}"
    CORS_ALLOWED_ORIGINS = "https://${local.edge_host}"
  })

  secret_env = [
    { name = "SPRING_DATASOURCE_PASSWORD", secret = "postgres-password" },
  ]

  depends_on = [module.secrets, module.cloud_sql, module.redis_vm, module.run_core]
}

module "run_agilite" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-agilite-core"
  image                 = var.pivot_agilite_image
  ingress               = "INGRESS_TRAFFIC_ALL"
  service_account_email = google_service_account.runtime["pivot-agilite"].email
  network_id            = module.network.network_id
  subnetwork_id         = module.network.subnet_id

  container_port      = 8082
  probe_port          = 8082
  startup_probe_path  = "/api/agilite/actuator/health/readiness"
  liveness_probe_path = "/api/agilite/actuator/health/liveness"
  min_instances       = 0
  max_instances       = 1
  timeout_seconds     = 3600
  session_affinity    = true
  invokers            = ["allUsers"]

  env = merge(local.redis_env, {
    SPRING_PROFILES_ACTIVE       = "prod"
    MANAGEMENT_SERVER_PORT       = "8082"
    SPRING_DATASOURCE_URL        = "jdbc:postgresql://${module.cloud_sql.private_ip}:5432/pivot?sslmode=require"
    SPRING_DATASOURCE_USERNAME   = "pivot"
    SPRING_FLYWAY_SCHEMAS        = "agilite"
    PIVOT_ACTIVEMQ_RELAY_ENABLED = "false"
    PIVOT_APP_URL                = "https://${local.edge_host}"
    CORS_ALLOWED_ORIGINS         = "https://${local.edge_host}"
  })

  secret_env = [
    { name = "SPRING_DATASOURCE_PASSWORD", secret = "postgres-password" },
  ]

  depends_on = [module.secrets, module.cloud_sql, module.redis_vm, module.run_core]
}

module "run_pilotage" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-pilotage-core"
  image                 = var.pivot_pilotage_image
  ingress               = "INGRESS_TRAFFIC_ALL"
  service_account_email = google_service_account.runtime["pivot-pilotage"].email
  network_id            = module.network.network_id
  subnetwork_id         = module.network.subnet_id

  container_port      = 8081
  probe_port          = 8081
  startup_probe_path  = "/api/pilotage/actuator/health/readiness"
  liveness_probe_path = "/api/pilotage/actuator/health/liveness"
  min_instances       = 0
  max_instances       = 1
  timeout_seconds     = 3600
  session_affinity    = true
  invokers            = ["allUsers"]

  env = merge(local.redis_env, {
    SPRING_PROFILES_ACTIVE       = "prod"
    MANAGEMENT_SERVER_PORT       = "8081"
    SPRING_DATASOURCE_URL        = "jdbc:postgresql://${module.cloud_sql.private_ip}:5432/pivot?sslmode=require"
    SPRING_DATASOURCE_USERNAME   = "pivot"
    SPRING_FLYWAY_SCHEMAS        = "pilotage"
    PIVOT_ACTIVEMQ_RELAY_ENABLED = "false"
    PIVOT_APP_URL                = "https://${local.edge_host}"
    CORS_ALLOWED_ORIGINS         = "https://${local.edge_host}"
  })

  secret_env = [
    { name = "SPRING_DATASOURCE_PASSWORD", secret = "postgres-password" },
  ]

  depends_on = [module.secrets, module.cloud_sql, module.redis_vm, module.run_core]
}

# --- Edge: pivot-ui nginx (SPA + reverse proxy) — the ONLY public entry point -
# No VPC egress (network_id omitted): it only calls the other run.app URLs.
# nginx.cloudrun.conf.template reads PIVOT_*_UPSTREAM (host only, no scheme) and
# proxies HTTPS with SNI + Host rewrite. listen $PORT=8080, /health returns 200.
module "run_edge" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-ui"
  image                 = var.pivot_ui_image
  ingress               = "INGRESS_TRAFFIC_ALL"
  service_account_email = google_service_account.runtime["pivot-ui"].email

  container_port      = 8080
  probe_port          = 8080
  startup_probe_path  = "/health"
  liveness_probe_path = "/health"
  min_instances       = 0
  max_instances       = 1
  invokers            = ["allUsers"]

  env = {
    PIVOT_CORE_UPSTREAM         = module.run_core.uri_host
    PIVOT_COLLABORATIF_UPSTREAM = module.run_collaboratif.uri_host
    PIVOT_AGILITE_UPSTREAM      = module.run_agilite.uri_host
    PIVOT_PILOTAGE_UPSTREAM     = module.run_pilotage.uri_host
  }
}

locals {
  labels = {
    env     = "managed-min"
    stack   = "cloudrun-nolb"
    managed = "terraform"
  }
}
