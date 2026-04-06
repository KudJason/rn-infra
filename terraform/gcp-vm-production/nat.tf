# Cloud NAT for worker VMs to access internet
# Allows workers to download packages without external IPs

resource "google_compute_router" "prod_router" {
  name    = "prod-router"
  network = "default"
  region  = var.region
}

resource "google_compute_address" "nat_ip" {
  name         = "prod-nat-ip"
  network_tier = "PREMIUM"
  region       = var.region
}

resource "google_compute_router_nat" "prod_nat" {
  name                               = "prod-nat"
  router                             = google_compute_router.prod_router.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    filter = "ERRORS_ONLY"
    enable = true
  }
}
