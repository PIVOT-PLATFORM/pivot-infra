terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- Cloud DNS ---------------------------------------------------------------
# Managed zone + A records pointing the service hostnames at the LB IP. The
# managed SSL cert (load-balancer module) only goes ACTIVE once these records
# resolve to the LB, so create the zone, delegate the domain at the registrar
# to the zone's name servers, then apply the A records.
#
# manage_zone=false lets an environment reuse an existing zone (e.g. one shared
# parent zone) and only add records.

resource "google_dns_managed_zone" "this" {
  count = var.manage_zone ? 1 : 0

  project     = var.project_id
  name        = var.zone_name
  dns_name    = var.dns_name # trailing dot, e.g. "pivot.example."
  description = "PIVOT platform managed zone"
}

locals {
  zone_name = var.manage_zone ? google_dns_managed_zone.this[0].name : var.zone_name
}

resource "google_dns_record_set" "a" {
  for_each = var.a_records

  project      = var.project_id
  managed_zone = local.zone_name
  name         = each.key # FQDN with trailing dot, e.g. "recette.pivot.example."
  type         = "A"
  ttl          = each.value.ttl
  rrdatas      = [each.value.ip]
}
