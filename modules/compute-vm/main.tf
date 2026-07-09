terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Network ---------------------------------------------------------------
# Dedicated VPC (not "default") — keeps the MVP host off the project's
# default network and its permissive default firewall rules.

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  project       = var.project_id
  name          = "${var.name}-subnet"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/24"
}

# --- Firewall ----------------------------------------------------------------
# nginx (docker-compose.prod.yml) is the only container bound to a host port
# (80/443) — pivot-core, postgres, redis, pgbouncer stay on the internal
# Docker networks (pivot-net-app/pivot-net-data) and are never reachable from
# outside the VM. So the only inbound host ports are 22 (ops), 80, 443.

resource "google_compute_firewall" "ssh" {
  project       = var.project_id
  name          = "${var.name}-allow-ssh"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = var.ssh_source_ranges
  target_tags   = ["${var.name}-vm"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# 0.0.0.0/0 is intentional here — this is the public web/API entrypoint
# (nginx :80/:443), not an internal service. Logged so unexpected traffic
# patterns are visible in Cloud Logging.
resource "google_compute_firewall" "http_https" {
  project       = var.project_id
  name          = "${var.name}-allow-http-https"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.name}-vm"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# --- Static external IP -----------------------------------------------------
# Reserved so PROD_SSH_HOST (EN07.5 deploy.yml secret) and any DNS A record
# stay stable across VM recreation.

resource "google_compute_address" "this" {
  project = var.project_id
  name    = "${var.name}-ip"
  region  = var.region
}

# --- Service account ---------------------------------------------------------
# Scoped to logging/monitoring only — the VM has no need to call any other
# GCP API (image pulls come from GHCR over the public internet, not GCR/AR).

resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "${var.name}-vm"
  display_name = "${var.name} Compute Engine VM"
}

resource "google_project_iam_member" "vm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

# --- Compute instance ---------------------------------------------------------
# Debian 12 + a startup-script installing Docker Engine/Compose plugin —
# deliberately NOT Container-Optimized OS: COS ships Docker but not the
# `docker compose` plugin pivot-core/docker-compose.prod.yml relies on.
#
# Deployment of docker-compose.prod.yml itself (and the secrets/ files it
# mounts) is out of scope here — that's EN07.5's job (GitHub Actions SSH +
# `docker compose pull && up -d` against PROD_DEPLOY_PATH). This module only
# provisions a host that's ready to receive it.

resource "google_compute_instance" "this" {
  project                   = var.project_id
  name                      = "${var.name}-vm"
  zone                      = var.zone
  machine_type              = var.machine_type
  tags                      = ["${var.name}-vm"]
  labels                    = var.labels
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id

    access_config {
      nat_ip = google_compute_address.this.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = templatefile("${path.module}/startup-script.sh", {
      deploy_user = var.ssh_user
    })
    # Only the instance-level ssh-keys entry above grants access — a
    # project-wide SSH key (added later via `gcloud compute project-info`,
    # by mistake or by another engineer) would otherwise also work here.
    block-project-ssh-keys = "true"
  }
}
