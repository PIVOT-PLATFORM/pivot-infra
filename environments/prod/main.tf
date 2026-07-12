terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Partial config on purpose — the bucket is created manually in
  # bootstrap/ (chicken-and-egg: Terraform can't create the backend it
  # then needs to store its own state in). Fill in at init time:
  #   terraform init -backend-config="bucket=<bucket-name>"
  #
  # Separate prefix from "mvp-test"/recette — own state file, own VM, never touched by a
  # `terraform apply` run against environments/recette.
  backend "gcs" {
    prefix = "prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "vm" {
  source = "../../modules/compute-vm"

  project_id        = var.project_id
  region            = var.region
  zone              = var.zone
  name              = "pivot-prod"
  machine_type      = var.machine_type
  ssh_user          = var.ssh_user
  ssh_public_key    = var.ssh_public_key
  ssh_source_ranges = var.ssh_source_ranges

  labels = {
    env     = "prod"
    managed = "terraform"
  }
}
