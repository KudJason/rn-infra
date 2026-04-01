# Production VM Firewall Rules

# Allow SSH to prod Core VM
resource "google_compute_firewall" "allow_prod_core_ssh" {
  name     = "rn-allow-ssh-prod-core"
  network  = "default"
  priority = 900

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = var.admin_ip_ranges
  target_tags   = ["prod-core-ssh", "prod-worker"]
}

# Allow HTTP/HTTPS to prod Core VM (for Ingress)
resource "google_compute_firewall" "allow_prod_core_web" {
  name    = "rn-allow-web-prod-core"
  network = "default"
  priority = 900

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = var.cloudflare_ipv4_ranges
  target_tags   = ["prod-core-web"]
}

# Deny all inbound to prod workers
resource "google_compute_firewall" "deny_all_prod_worker_inbound" {
  name    = "rn-deny-prod-worker-inbound"
  network = "default"

  deny { protocol = "all" }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["prod-worker"]
  priority      = 1000
  direction     = "INGRESS"
}

# Allow cluster internal traffic for prod
resource "google_compute_firewall" "allow_prod_cluster_internal" {
  name     = "rn-allow-prod-cluster-internal"
  network  = "default"
  priority = 900

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_tags = ["prod-core-vm", "prod-worker"]
  target_tags = ["prod-core-vm", "prod-worker"]
}

# Allow K3s API server port from prod workers
resource "google_compute_firewall" "allow_prod_k3s_api" {
  name     = "rn-allow-prod-k3s-api"
  network  = "default"
  priority = 900

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
  source_tags = ["prod-worker"]
  target_tags = ["prod-core-vm"]
}
