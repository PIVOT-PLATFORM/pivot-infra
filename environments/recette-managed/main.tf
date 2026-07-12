terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Dedicated state prefix so the managed stack is built ALONGSIDE the live VM
  # (environments/recette, prefix "mvp-test") without touching its state. Once
  # the managed stack serves recette traffic and the VM is decommissioned
  # (migration Phase 7), this collapses into the "recette" prefix.
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

# --- Runtime service accounts (per Cloud Run service) ------------------------
# Least privilege: one identity per service. Created here (env-specific
# identities) so the foundation modules can grant them read access now; the
# Cloud Run module (Phase 3) attaches them to the services.
resource "google_service_account" "runtime" {
  for_each = toset(["pivot-core", "pivot-collaboratif"])

  project      = var.project_id
  account_id   = "sa-${each.value}"
  display_name = "Cloud Run runtime — ${each.value}"
}

# --- Foundation ---------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  region     = var.region
  name       = "pivot-recette"

  # Direct VPC egress puts Cloud Run instances in this subnet, so the subnet
  # range is the source that must reach the data tier (Postgres/Redis/ActiveMQ).
  internal_ingress_ranges = [var.subnet_cidr]
  subnet_cidr             = var.subnet_cidr
}

# BUILD cost posture: no Serverless VPC connector (Cloud Run uses Direct VPC
# egress instead — see the run_* modules). Removes a ~$14/mo always-on component.

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = var.project_id
  region     = var.region

  # Runtime SAs pull images; deployer SAs (iam-wif) push them.
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
    "pivot-collaboratif-ui"   = { account_id = "dep-pivot-collab-ui", project_roles = ["roles/artifactregistry.writer"] }
    # Orchestrator: deploys to Cloud Run. serviceAccountUser on the runtime SAs
    # is bound below (per-SA, not project-wide).
    "pivot-infra" = { account_id = "dep-orchestrator", project_roles = ["roles/run.admin", "roles/artifactregistry.writer"] }
  }
}

# The orchestrator SA must be able to act-as each runtime SA to deploy a
# revision that runs as it. Scoped per-SA (not project-wide serviceAccountUser).
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

  secrets = {
    "postgres-password" = { accessors = [for sa in google_service_account.runtime : "serviceAccount:${sa.email}"] }
    "mail-password"     = { accessors = ["serviceAccount:${google_service_account.runtime["pivot-core"].email}"] }
    "otp-secret"        = { accessors = ["serviceAccount:${google_service_account.runtime["pivot-core"].email}"] }
    "redis-auth"        = { accessors = [for sa in google_service_account.runtime : "serviceAccount:${sa.email}"] }
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

  # BUILD cost posture: smallest shared-core tier, ZONAL, no HA. Can be stopped
  # when idle. Prod uses a larger tier + REGIONAL (see plan decision #3/#4).
  tier                = "db-f1-micro"
  availability_type   = "ZONAL"
  deletion_protection = false
}

# BUILD cost posture: no managed Memorystore (~$35/mo). Redis is co-located as a
# cache container on the dev VM below (run_redis=true). Prod uses managed
# Memorystore (AUTH+TLS) instead.

module "activemq" {
  source = "../../modules/activemq-vm"

  project_id       = var.project_id
  zone             = var.zone
  name             = "pivot-recette-activemq"
  subnet_id        = module.network.subnet_id
  machine_type     = "e2-micro" # dev sizing
  run_redis        = true       # co-locate Redis cache (replaces Memorystore in dev)
  assign_public_ip = true       # dev egress to pull Docker + images (no Cloud NAT)

  labels = local.labels
}

# --- Application tier (Cloud Run) --------------------------------------------
# Shared env/secret wiring notes (coordinate with the service repos):
#  - probe_port: actuator runs on a separate management port (8081 / 9083) that
#    Cloud Run's probe (serving port only) can't reach. Either expose readiness
#    on the serving port for prod, or set management.server.port = serving port.
#    Marked TODO on each service below.
#  - SECRET_* env vars rely on Spring relaxed binding to the same `secret.*`
#    keys the compose configtree provides (/run/secrets). Confirm in
#    application-prod.yml, or switch to a file-mount shim (module README).

module "run_core" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-core"
  image                 = var.pivot_core_image
  service_account_email = google_service_account.runtime["pivot-core"].email
  network_id            = module.network.network_id
  subnetwork_id         = module.network.subnet_id

  container_port = 8080
  probe_port     = 8080
  # MANAGEMENT_SERVER_PORT=8080 moves actuator onto the serving port so Cloud
  # Run probes can reach it (env-driven, no app change). At the same port,
  # actuator sits under the /api context-path -> probe paths below.
  startup_probe_path  = "/api/actuator/health/readiness"
  liveness_probe_path = "/api/actuator/health/liveness"
  min_instances       = 0 # recette: scale to zero
  max_instances       = 2
  invokers            = ["allUsers"] # public web app; boundary is ingress=internal+LB

  env = {
    SPRING_PROFILES_ACTIVE     = "prod"
    MANAGEMENT_SERVER_PORT     = "8080"
    SPRING_DATASOURCE_URL      = "jdbc:postgresql://${module.cloud_sql.private_ip}:5432/pivot"
    SPRING_DATASOURCE_USERNAME = "pivot"
    # Dev: self-hosted Redis on the VM, no TLS/AUTH (VPC-internal only).
    SPRING_DATA_REDIS_HOST        = module.activemq.redis_host
    SPRING_DATA_REDIS_PORT        = tostring(module.activemq.redis_port)
    SPRING_DATA_REDIS_SSL_ENABLED = "false"
    SPRING_MAIL_HOST              = var.smtp_host
    SPRING_MAIL_PORT              = tostring(var.smtp_port)
    SPRING_MAIL_USERNAME          = var.smtp_username
    PIVOT_MAIL_FROM               = var.mail_from
    PIVOT_APP_URL                 = "https://${var.recette_host}"
    CORS_ALLOWED_ORIGINS          = "https://${var.recette_host}"
  }

  # Env-var names verified against pivot-core application.yml — the app reads
  # these directly (env takes precedence over the configtree fallback), so no
  # app change and no file-mount shim is needed for secret delivery. No Redis
  # password in dev (self-hosted unauth Redis).
  secret_env = [
    { name = "SPRING_DATASOURCE_PASSWORD", secret = "postgres-password" },
    { name = "SPRING_MAIL_PASSWORD", secret = "mail-password" },
    { name = "PIVOT_AUTH_OTP_SECRET", secret = "otp-secret" },
  ]

  depends_on = [module.secrets, module.cloud_sql, module.activemq]
}

module "run_collaboratif" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "pivot-collaboratif-core"
  image                 = var.pivot_collaboratif_image
  service_account_email = google_service_account.runtime["pivot-collaboratif"].email
  network_id            = module.network.network_id
  subnetwork_id         = module.network.subnet_id

  container_port      = 8083
  probe_port          = 8083
  startup_probe_path  = "/api/collaboratif/actuator/health/readiness"
  liveness_probe_path = "/api/collaboratif/actuator/health/liveness"

  # BUILD cost posture: scale to zero in recette (accept cold start + WS
  # reconnect). Prod keeps min=1 for live boards. Still sticky + long timeout.
  min_instances    = 0
  max_instances    = 2
  timeout_seconds  = 3600
  session_affinity = true
  invokers         = ["allUsers"]

  env = {
    SPRING_PROFILES_ACTIVE        = "prod"
    MANAGEMENT_SERVER_PORT        = "8083" # actuator on the serving port for Cloud Run probes
    SPRING_DATASOURCE_URL         = "jdbc:postgresql://${module.cloud_sql.private_ip}:5432/pivot"
    SPRING_DATASOURCE_USERNAME    = "pivot"
    SPRING_DATA_REDIS_HOST        = module.activemq.redis_host
    SPRING_DATA_REDIS_PORT        = tostring(module.activemq.redis_port)
    SPRING_DATA_REDIS_SSL_ENABLED = "false"
    PIVOT_ACTIVEMQ_RELAY_HOST     = module.activemq.internal_ip
    PIVOT_ACTIVEMQ_RELAY_PORT     = tostring(module.activemq.stomp_port)
    # TODO(collaboratif-core): trust the LB peer for X-Forwarded-For/Proto.
    PIVOT_APP_URL        = "https://${var.recette_host}"
    CORS_ALLOWED_ORIGINS = "https://${var.recette_host}"
  }

  secret_env = [
    { name = "SPRING_DATASOURCE_PASSWORD", secret = "postgres-password" },
  ]

  depends_on = [module.secrets, module.cloud_sql, module.activemq]
}

# --- Edge: HTTPS LB + SPA/CDN + DNS ------------------------------------------

module "lb" {
  source = "../../modules/load-balancer"

  project_id      = var.project_id
  region          = var.region
  name            = "pivot-recette-lb"
  ssl_domains     = [var.recette_host]
  spa_bucket_name = var.spa_bucket_name

  services = {
    core         = { service_name = module.run_core.service_name, timeout_sec = 60, session_affinity = false }
    collaboratif = { service_name = module.run_collaboratif.service_name, timeout_sec = 3600, session_affinity = true }
  }

  # nginx.conf longest-prefix parity: module prefixes before the core catch-all.
  path_rules = [
    { paths = ["/api/collaboratif/*", "/ws/collaboratif/*"], service_key = "collaboratif" },
    { paths = ["/api/*"], service_key = "core" },
  ]
}

module "dns" {
  source = "../../modules/dns"

  project_id  = var.project_id
  manage_zone = var.manage_dns_zone
  zone_name   = var.dns_zone_name
  dns_name    = var.dns_zone_dns_name

  a_records = {
    "${var.recette_host}." = { ip = module.lb.ip_address, ttl = 300 }
  }
}

locals {
  labels = {
    env     = "recette"
    stack   = "managed"
    managed = "terraform"
  }
}
