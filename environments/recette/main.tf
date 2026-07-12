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
  # Prefix stays "mvp-test" even though this directory is now "recette" — this environment
  # IS the former mvp-test VM, promoted in place (not recreated). Changing the prefix would
  # point Terraform at an empty state and either orphan the real VM or try to recreate it.
  backend "gcs" {
    prefix = "mvp-test"
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
  # Stays "pivot-mvp" for the same reason as the backend prefix above — this is the existing
  # VM, not a new one. GCP resource names (instance, VPC, firewall rules...) will keep
  # showing "pivot-mvp-*" even though this is now the "recette" environment.
  name              = "pivot-mvp"
  machine_type      = var.machine_type
  ssh_user          = var.ssh_user
  ssh_public_key    = var.ssh_public_key
  ssh_source_ranges = var.ssh_source_ranges

  labels = {
    env     = "recette"
    managed = "terraform"
  }
}
