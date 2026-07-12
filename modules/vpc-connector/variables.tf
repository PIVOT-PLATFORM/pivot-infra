variable "project_id" {
  type        = string
  description = "GCP project hosting the connector."
}

variable "region" {
  type        = string
  description = "Region (must match the Cloud Run services and subnet)."
}

variable "name" {
  type        = string
  default     = "pivot-connector"
  description = "Connector name (<= 25 chars)."
}

variable "network_name" {
  type        = string
  description = "VPC name the connector attaches to (network module output network_name)."
}

variable "connector_cidr" {
  type        = string
  default     = "10.10.8.0/28"
  description = "Dedicated /28 for the connector. Must not overlap the primary subnet or PSA range."
}

variable "min_instances" {
  type        = number
  default     = 2
  description = "Minimum connector instances (2 is the platform minimum)."
}

variable "max_instances" {
  type        = number
  default     = 3
  description = "Maximum connector instances. Raise in prod for more throughput."
}

variable "machine_type" {
  type        = string
  default     = "e2-micro"
  description = "Connector instance machine type."
}
