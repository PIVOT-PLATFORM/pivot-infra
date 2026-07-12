variable "project_id" {
  type        = string
  description = "GCP project."
}

variable "region" {
  type        = string
  description = "Region (must match the VPC)."
}

variable "name" {
  type        = string
  default     = "pivot-redis"
  description = "Memorystore instance name."
}

variable "network_id" {
  type        = string
  description = "VPC self-link/id (network module output network_id)."
}

variable "psa_connection" {
  type        = string
  description = "PSA connection id to depend on (network module output psa_connection)."
}

variable "tier" {
  type        = string
  default     = "BASIC"
  description = "BASIC (single node, recette) or STANDARD_HA (replica + failover, prod)."

  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "tier must be BASIC or STANDARD_HA."
  }
}

variable "memory_size_gb" {
  type        = number
  default     = 1
  description = "Instance memory (GB)."
}

variable "redis_version" {
  type        = string
  default     = "REDIS_7_2"
  description = "Redis engine version."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to the instance."
}
