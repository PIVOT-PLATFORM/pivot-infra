terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Artifact Registry (Docker) ---------------------------------------------
# Replaces GHCR (ghcr.io/pivot-platform/*) as the image registry. Service
# release.yml pipelines push here keyless via Workload Identity Federation
# (see modules/iam-wif), Cloud Run pulls by immutable digest.
#
# One Docker repository holds every service image (pivot-core, pivot-ui,
# pivot-collaboratif-core, ...). Images are addressed by name+digest, e.g.
#   europe-west1-docker.pkg.dev/<project>/<repo>/pivot-core@sha256:...
# so a single repo is sufficient and keeps IAM simple.

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "PIVOT platform container images (replaces GHCR)"
  format        = "DOCKER"

  docker_config {
    # Immutable tags: once pushed, a tag cannot be overwritten. Deploys use
    # digests anyway (plan: "digest is the contract"), but this also stops a
    # re-pushed semver tag from silently changing an artifact — the exact
    # class of incident CICD-002 flagged with GHCR floating tags.
    immutable_tags = true
  }

  # Keep storage bounded: retain recent + tagged images, delete old untagged
  # layers (build cache, superseded digests) after a grace period.
  cleanup_policy_dry_run = var.cleanup_dry_run

  cleanup_policies {
    id     = "keep-recent-tagged"
    action = "KEEP"
    condition {
      tag_state = "TAGGED"
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = var.untagged_ttl
    }
  }

  labels = var.labels
}

# --- Reader access for runtime service accounts -----------------------------
# Cloud Run runtime SAs need to pull images. Writer access is granted to the
# per-repo deployer SAs in modules/iam-wif (least privilege: only CI writes).

resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = toset(var.reader_members)

  project    = google_artifact_registry_repository.docker.project
  location   = google_artifact_registry_repository.docker.location
  repository = google_artifact_registry_repository.docker.name
  role       = "roles/artifactregistry.reader"
  member     = each.value
}
