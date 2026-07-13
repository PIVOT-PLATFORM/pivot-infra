variable "project_id" {
  type        = string
  description = "GCP project hosting the VPC."
}

variable "region" {
  type        = string
  description = "Region for the subnet (e.g. europe-west1)."
}

variable "name" {
  type        = string
  description = "Name prefix for VPC/subnet/firewall resources (e.g. pivot-recette)."
}

variable "subnet_cidr" {
  type        = string
  default     = "10.10.0.0/24"
  description = "Primary subnet range. Hosts the ActiveMQ VM and serves as a trusted internal range."
}

variable "psa_prefix_length" {
  type        = number
  default     = 16
  description = "Prefix length for the Private Service Access peering range (Cloud SQL/Memorystore allocate private IPs from it)."
}

variable "iap_ssh_target_tags" {
  type        = list(string)
  default     = ["activemq"]
  description = "Network tags that IAP SSH (35.235.240.0/20 -> :22) applies to."
}

variable "internal_ingress_ranges" {
  type        = list(string)
  default     = []
  description = "Source ranges allowed to reach internal data ports (e.g. the Serverless VPC connector /28 and the subnet range)."
}

variable "internal_ingress_ports" {
  type        = list(string)
  default     = ["5432", "6379", "61613"]
  description = "Internal data-tier ports: Postgres, Redis, ActiveMQ STOMP."
}
