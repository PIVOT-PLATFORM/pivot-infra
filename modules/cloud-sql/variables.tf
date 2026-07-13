variable "project_id" {
  type        = string
  description = "GCP project."
}

variable "region" {
  type        = string
  description = "Region (must match the VPC/connector)."
}

variable "instance_name" {
  type        = string
  description = "Cloud SQL instance name (e.g. pivot-recette-pg)."
}

variable "network_id" {
  type        = string
  description = "VPC self-link/id for the private IP (network module output network_id)."
}

variable "psa_connection" {
  type        = string
  description = "PSA connection id to depend on before creating the private-IP instance (network module output psa_connection)."
}

variable "database_name" {
  type        = string
  default     = "pivot"
  description = "Application database name (the 4 schemas live inside it)."
}

variable "tier" {
  type        = string
  default     = "db-g1-small"
  description = "Machine tier. Small for recette; larger custom tier for prod."
}

variable "availability_type" {
  type        = string
  default     = "ZONAL"
  description = "ZONAL (single-zone, recette) or REGIONAL (HA, prod)."

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "max_connections" {
  type        = number
  default     = 100
  description = "Postgres max_connections. Size vs (max Cloud Run instances × Hikari pool)."
}

variable "backup_start_time" {
  type        = string
  default     = "02:00"
  description = "Daily backup window start (UTC, HH:MM)."
}

variable "transaction_log_retention_days" {
  type        = number
  default     = 7
  description = "WAL retention for PITR (days). 7 recette / up to 35 prod."
}

variable "retained_backups" {
  type        = number
  default     = 7
  description = "Number of automated backups to retain. 7 recette / 30 prod."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Block accidental instance deletion. Keep true in prod."
}
