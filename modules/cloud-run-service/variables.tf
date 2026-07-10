variable "project_id" { type = string }
variable "region" { type = string }

variable "name" {
  type        = string
  description = "Cloud Run service name (e.g. pivot-core)."
}

variable "image" {
  type        = string
  description = "Image by DIGEST: <region>-docker.pkg.dev/<proj>/pivot/<service>@sha256:<digest>."
}

variable "service_account_email" {
  type        = string
  description = "Runtime SA email (least privilege, per service)."
}

variable "network_id" {
  type        = string
  description = "VPC id for Direct VPC egress (network module output network_id)."
}

variable "subnetwork_id" {
  type        = string
  description = "Subnet id for Direct VPC egress (network module output subnet_id)."
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Port traffic is routed to (pivot-core 8080, collaboratif-core 8083)."
}

variable "probe_port" {
  type        = number
  default     = 8080
  description = <<-EOT
    Port for health probes. Cloud Run probes target the serving port. Actuator
    lives on a separate management port (8081/9083) NOT reachable by Cloud Run's
    probe — so either expose readiness on the serving port for prod, or set the
    management port equal to the serving port (coordinate in the service's
    application-prod.yml). See README.
  EOT
}

variable "startup_probe_path" {
  type    = string
  default = "/actuator/health/readiness"
}

variable "liveness_probe_path" {
  type    = string
  default = "/actuator/health/liveness"
}

variable "startup_initial_delay" {
  type    = number
  default = 20
}

variable "startup_failure_threshold" {
  type    = number
  default = 30
}

variable "min_instances" {
  type        = number
  default     = 0
  description = "0 for recette (scale to zero). >=1 for prod / WebSocket services."
}

variable "max_instances" {
  type    = number
  default = 4
}

variable "concurrency" {
  type    = number
  default = 80
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "1Gi"
}

variable "timeout_seconds" {
  type        = number
  default     = 300
  description = "Request timeout. Raise to 3600 for the WebSocket/STOMP service so long-lived /ws connections aren't cut."
}

variable "session_affinity" {
  type        = bool
  default     = false
  description = "Best-effort sticky sessions. Enable for the WebSocket service (correctness comes from the ActiveMQ relay, affinity is UX/perf)."
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables."
}

variable "secret_env" {
  type = list(object({
    name    = string
    secret  = string
    version = optional(string, "latest")
  }))
  default     = []
  description = "Secret Manager values injected as env vars."
}

variable "secret_volumes" {
  type = list(object({
    name       = string # volume name
    secret     = string # Secret Manager secret id
    file_name  = string # filename under mount_path (== Spring configtree key, e.g. secret.datasource-password)
    mount_path = string # e.g. /run/secrets  (must be unique per volume)
    version    = optional(string, "latest")
  }))
  default     = []
  description = "Secret Manager values mounted as files (Spring configtree). See README on multi-secret single-dir caveat."
}

variable "invokers" {
  type        = list(string)
  default     = []
  description = "Members granted roles/run.invoker (LB/gateway identity)."
}

variable "deletion_protection" {
  type    = bool
  default = false
}
