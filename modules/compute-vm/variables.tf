variable "project_id" {
  description = "GCP project ID the VM is created in."
  type        = string
}

variable "region" {
  description = "GCP region for the subnet and static IP."
  type        = string
}

variable "zone" {
  description = "GCP zone for the compute instance."
  type        = string
}

variable "name" {
  description = "Base name for all resources created by this module (VM, network, firewall rules...)."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type. e2-medium (2 vCPU / 4GB) covers nginx + pivot-core (JVM) + pgbouncer + postgres + redis for an MVP test load."
  type        = string
  default     = "e2-medium"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB. Hosts the OS, Docker images, and (for this MVP setup) the postgres/redis named volumes."
  type        = number
  default     = 30
}

variable "ssh_user" {
  description = "Username for SSH access — must match the user configured as PROD_SSH_USER in pivot-core's deploy.yml (EN07.5)."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key (contents, not a path) granted access to ssh_user. Pair it with the private key stored in the PROD_SSH_KEY GitHub secret."
  type        = string
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to reach port 22. No default on purpose — an MVP test box is still a real internet-facing host; pass your own IP (e.g. [\"a.b.c.d/32\"]) or your office/VPN range, never 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.ssh_source_ranges) > 0
    error_message = "ssh_source_ranges must not be empty — SSH access must be scoped to known ranges."
  }
}

variable "labels" {
  description = "Labels applied to all resources."
  type        = map(string)
  default     = {}
}
