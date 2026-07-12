terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- VPC + subnet ------------------------------------------------------------
# Custom VPC (not "default") for the managed stack. The subnet enables Private
# Google Access so resources without a public IP can still reach Google APIs
# (Secret Manager, Artifact Registry, logging) over internal routing.

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = "${var.name}-subnet"
  network                  = google_compute_network.this.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# --- Private Service Access (for Cloud SQL / Memorystore private IP) ---------
# Managed data services get a private IP inside a Google-managed range peered
# into this VPC. This reserves the peering range and establishes the peering
# connection; the Cloud SQL / Memorystore modules then request private IPs.

resource "google_compute_global_address" "psa_range" {
  project       = var.project_id
  name          = "${var.name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
}

# --- Firewall: IAP SSH (ops access to the ActiveMQ VM, no public SSH) --------
# The only VM in the managed stack (ActiveMQ) has no public IP. Ops reach it
# over Identity-Aware Proxy tunneling, whose forwarders live in 35.235.240.0/20.

resource "google_compute_firewall" "iap_ssh" {
  project       = var.project_id
  name          = "${var.name}-allow-iap-ssh"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = var.iap_ssh_target_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# --- Firewall: internal data-tier access ------------------------------------
# Allow the Serverless VPC connector range (and anything else the environment
# passes) to reach the data ports it needs: Postgres 5432, Redis 6379,
# ActiveMQ STOMP 61613. Deny-by-default otherwise (custom VPC has no implicit
# allow beyond the auto default-deny).

resource "google_compute_firewall" "internal_data" {
  count = length(var.internal_ingress_ranges) > 0 ? 1 : 0

  project       = var.project_id
  name          = "${var.name}-allow-internal-data"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = var.internal_ingress_ranges

  allow {
    protocol = "tcp"
    ports    = var.internal_ingress_ports
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
