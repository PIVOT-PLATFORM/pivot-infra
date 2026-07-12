variable "project_id" { type = string }

variable "manage_zone" {
  type        = bool
  default     = true
  description = "Create the managed zone (true) or reuse an existing one by name (false)."
}

variable "zone_name" {
  type        = string
  description = "Managed zone resource name (when manage_zone=true it is created; when false it must already exist)."
}

variable "dns_name" {
  type        = string
  default     = ""
  description = "Zone DNS name with trailing dot (e.g. \"pivot.example.\"). Required when manage_zone=true."
}

variable "a_records" {
  description = <<-EOT
    Map of FQDN (trailing dot) -> { ip, ttl }. Point service hostnames at the LB IP.
    Example: { "recette.pivot.example." = { ip = "<lb_ip>", ttl = 300 } }
    Use a low TTL (300) around a cutover so the switch propagates fast.
  EOT
  type = map(object({
    ip  = string
    ttl = number
  }))
  default = {}
}
