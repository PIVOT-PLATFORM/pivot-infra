terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Memorystore for Redis ---------------------------------------------------
# Replaces the redis container. Two hardening wins over the compose stack,
# which ran Redis unauthenticated with only network isolation (compose L240):
#   - AUTH enabled  -> a password is required (stored as the `redis-auth` secret)
#   - in-transit TLS (SERVER_AUTHENTICATION)
# Private Service Access connect mode -> private IP on the VPC, no public
# endpoint. STANDARD_HA gives a replica + automatic failover (prod).

resource "google_redis_instance" "this" {
  project                 = var.project_id
  name                    = var.name
  region                  = var.region
  tier                    = var.tier # BASIC (recette) | STANDARD_HA (prod)
  memory_size_gb          = var.memory_size_gb
  redis_version           = var.redis_version
  authorized_network      = var.network_id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  depends_on = [var.psa_connection]

  labels = var.labels
}
