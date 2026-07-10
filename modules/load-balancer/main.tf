terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# --- External HTTPS Load Balancer (the gateway, replacing nginx) --------------
# Translates pivot-ui/nginx.conf into GCP-native routing:
#   - TLS termination + HSTS at the edge (Google-managed cert)
#   - SPA served from a GCS bucket + Cloud CDN (default route)
#   - /api/*, /api|ws/{module}/* routed to Cloud Run via Serverless NEGs
# The nginx longest-prefix table maps 1:1 onto the URL-map path rules; missing
# module services return their NEG's 503 exactly like nginx's lazy resolver did.

# Global anycast IP for the LB.
resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "${var.name}-ip"
}

# --- Serverless NEG + backend service per Cloud Run service ------------------
resource "google_compute_region_network_endpoint_group" "neg" {
  for_each = var.services

  project               = var.project_id
  name                  = "${var.name}-neg-${each.key}"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = each.value.service_name
  }
}

resource "google_compute_backend_service" "svc" {
  for_each = var.services

  project               = var.project_id
  name                  = "${var.name}-be-${each.key}"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  timeout_sec           = each.value.timeout_sec
  # WebSocket service: sticky sessions (best-effort; correctness via ActiveMQ relay).
  session_affinity = each.value.session_affinity ? "GENERATED_COOKIE" : "NONE"

  backend {
    group = google_compute_region_network_endpoint_group.neg[each.key].id
  }
  # Serverless NEG backends take no health check.
}

# --- SPA bucket + Cloud CDN (default route) ---------------------------------
resource "google_storage_bucket" "spa" {
  project                     = var.project_id
  name                        = var.spa_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # SPA pushState fallback (nginx try_files parity)
  }
}

# Public read for the SPA assets served through the CDN.
resource "google_storage_bucket_iam_member" "public" {
  count = var.spa_public ? 1 : 0

  bucket = google_storage_bucket.spa.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "spa" {
  project     = var.project_id
  name        = "${var.name}-spa"
  bucket_name = google_storage_bucket.spa.name
  enable_cdn  = true

  cdn_policy {
    cache_mode  = "CACHE_ALL_STATIC"
    client_ttl  = 3600
    default_ttl = 3600
    max_ttl     = 86400
  }
}

# --- URL map (the routing table) --------------------------------------------
resource "google_compute_url_map" "this" {
  project         = var.project_id
  name            = "${var.name}-urlmap"
  default_service = google_compute_backend_bucket.spa.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "main"
  }

  path_matcher {
    name            = "main"
    default_service = google_compute_backend_bucket.spa.id

    dynamic "path_rule" {
      for_each = var.path_rules
      content {
        paths   = path_rule.value.paths
        service = google_compute_backend_service.svc[path_rule.value.service_key].id
      }
    }
  }
}

# --- Managed TLS + HTTPS proxy + forwarding rule ----------------------------
# The managed cert only goes ACTIVE once the domain's A record points at
# google_compute_global_address.lb (handled by the dns module). Until then the
# LB serves a provisioning cert.
resource "google_compute_managed_ssl_certificate" "this" {
  project = var.project_id
  name    = "${var.name}-cert"

  managed {
    domains = var.ssl_domains
  }
}

resource "google_compute_target_https_proxy" "this" {
  project          = var.project_id
  name             = "${var.name}-https-proxy"
  url_map          = google_compute_url_map.this.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "${var.name}-https"
  target                = google_compute_target_https_proxy.this.id
  ip_address            = google_compute_global_address.lb.address
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# --- HTTP :80 -> HTTPS redirect (nginx :80 redirect parity) -----------------
resource "google_compute_url_map" "redirect" {
  project = var.project_id
  name    = "${var.name}-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "${var.name}-http"
  target                = google_compute_target_http_proxy.redirect.id
  ip_address            = google_compute_global_address.lb.address
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
