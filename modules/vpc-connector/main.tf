terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Serverless VPC Access connector ----------------------------------------
# Gives Cloud Run services private-IP reachability into the VPC: Cloud SQL and
# Memorystore (over PSA) and the ActiveMQ VM. Needs its own dedicated /28 that
# must not overlap the primary subnet or the PSA range.
#
# Egress is set to PRIVATE_RANGES_ONLY at the Cloud Run service level (see
# modules/cloud-run-service): only RFC1918 traffic uses the connector, so
# public egress (SMTP relay, OIDC issuer) keeps taking the normal path.

resource "google_vpc_access_connector" "this" {
  project       = var.project_id
  name          = var.name
  region        = var.region
  network       = var.network_name
  ip_cidr_range = var.connector_cidr
  min_instances = var.min_instances
  max_instances = var.max_instances
  machine_type  = var.machine_type
}
