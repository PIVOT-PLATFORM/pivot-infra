terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- ActiveMQ broker VM (the one residual non-serverless component) ----------
# collaboratif-core uses Spring's STOMP broker relay -> it needs a real broker
# speaking STOMP over TCP :61613 with persistent KahaDB. No managed GCP service
# offers that, and Cloud Run/Pub-Sub can't host it (see plan §1.6). So a single
# small VM with a dedicated PERSISTENT disk for KahaDB, private IP only,
# reachable from Cloud Run over the VPC connector on :61613. SSH is IAP-only
# (no public IP, no access_config) — the network module opens 35.235.240.0/20
# -> :22 for the `activemq` tag.

# Dedicated persistent disk for KahaDB — survives VM recreation (unlike the
# compose stack's boot-disk volumes). This is the "data persistence" property
# for the broker's message store.
resource "google_compute_disk" "kahadb" {
  count   = var.run_activemq ? 1 : 0
  project = var.project_id
  name    = "${var.name}-kahadb"
  zone    = var.zone
  type    = "pd-ssd"
  size    = var.data_disk_size_gb

  # NOTE: prod should guard this disk against accidental deletion (KahaDB store).
  # Left unguarded here because recette is a throwaway BUILD env that gets torn
  # down / recreated on demand for cost control. Re-add prevent_destroy (or use
  # a deletion policy) for the prod environment.
}

resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "${var.name}-vm"
  display_name = "ActiveMQ broker VM"
}

resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_instance" "this" {
  project                   = var.project_id
  name                      = "${var.name}-vm"
  zone                      = var.zone
  machine_type              = var.machine_type
  tags                      = ["activemq"]
  labels                    = var.labels
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  dynamic "attached_disk" {
    for_each = var.run_activemq ? [1] : []
    content {
      source      = google_compute_disk.kahadb[0].id
      device_name = "kahadb"
    }
  }

  # Private IP by default (no access_config). In dev (assign_public_ip=true) an
  # ephemeral external IP is added for EGRESS ONLY — the VM needs to pull Docker
  # + the redis/activemq images at boot, and there is no Cloud NAT. Inbound stays
  # locked: the custom VPC denies by default and only the IAP-SSH + internal-data
  # firewall rules allow traffic (no public inbound). Prod keeps this false and
  # uses private images (Artifact Registry via Private Google Access) or a NAT.
  network_interface {
    subnetwork = var.subnet_id

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  service_account {
    email = google_service_account.vm.email
    # Scoped roles via IAM above, not a blanket cloud-platform scope.
    scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"]
  }

  metadata = {
    block-project-ssh-keys = "true"
    startup-script = templatefile("${path.module}/startup-script.sh", {
      run_activemq   = var.run_activemq
      activemq_image = var.activemq_image
      stomp_port     = var.stomp_port
      run_redis      = var.run_redis
      redis_image    = var.redis_image
      redis_port     = var.redis_port
    })
  }
}
