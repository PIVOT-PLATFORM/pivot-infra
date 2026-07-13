variable "project_id" {
  type        = string
  description = "GCP project."
}

variable "zone" {
  type        = string
  description = "Zone for the VM and its disk (e.g. europe-west1-b)."
}

variable "name" {
  type        = string
  default     = "pivot-activemq"
  description = "Name prefix for the VM, disk and SA."
}

variable "subnet_id" {
  type        = string
  description = "Subnet id for the private-IP NIC (network module output subnet_id)."
}

variable "machine_type" {
  type        = string
  default     = "e2-small"
  description = "Broker VM machine type."
}

variable "data_disk_size_gb" {
  type        = number
  default     = 20
  description = "Persistent KahaDB disk size (GB)."
}

variable "run_activemq" {
  type        = bool
  default     = true
  description = "Run the ActiveMQ broker (+ its KahaDB persistent disk). Set false for a Redis-only VM (managed-min uses the in-memory SimpleBroker, so no ActiveMQ is needed — this VM then just hosts Redis)."
}

variable "activemq_image" {
  type        = string
  default     = "apache/activemq-classic:6.2.0"
  description = "Broker container image (matches the compose stack's broker)."
}

variable "stomp_port" {
  type        = number
  default     = 61613
  description = "STOMP connector port the broker relay connects to."
}

variable "assign_public_ip" {
  type        = bool
  default     = false
  description = "Attach an ephemeral external IP for egress (dev: pull Docker + images at boot, no Cloud NAT). Inbound stays firewall-locked. Prod: keep false."
}

variable "run_redis" {
  type        = bool
  default     = false
  description = "Co-locate a Redis cache container on this VM (dev cost saver, replaces Memorystore). Prod: keep false and use managed Memorystore."
}

variable "redis_image" {
  type        = string
  default     = "redis:7-alpine"
  description = "Redis image when run_redis=true."
}

variable "redis_port" {
  type        = number
  default     = 6379
  description = "Redis port exposed on the VM's private IP."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to the VM."
}
