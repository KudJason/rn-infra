# Production Firewall Rules

resource "google_compute_firewall" "allow_prod_core_ssh" {
  name        = "allow-prod-core-ssh"
  network     = "default"
  description = "Allow SSH to production Core VM from admin IP"

  source_ranges = var.admin_ip_ranges
  target_tags   = ["prod-core-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_prod_core_web" {
  name        = "allow-prod-core-web"
  network     = "default"
  description = "Allow HTTP/HTTPS to production Core VM"

  source_ranges = concat(["0.0.0.0/0"], var.cloudflare_ipv4_ranges)
  target_tags   = ["prod-core-web"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "allow_prod_worker_ssh" {
  name        = "allow-prod-worker-ssh"
  network     = "default"
  description = "Allow SSH to production workers from Core VM only"

  source_tags = ["prod-core-ssh"]
  target_tags = ["prod-worker-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_prod_cluster_internal" {
  name        = "allow-prod-cluster-internal"
  network     = "default"
  description = "Allow all internal cluster communication"

  source_tags = ["prod-core-ssh", "prod-worker-ssh"]
  target_tags = ["prod-core-ssh", "prod-worker-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
}

resource "google_compute_firewall" "allow_prod_k3s_api" {
  name        = "allow-prod-k3s-api"
  network     = "default"
  description = "Allow k3s API from workers to Core"

  source_tags = ["prod-worker-ssh"]
  target_tags = ["prod-core-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

resource "google_compute_firewall" "deny_all_prod_worker_inbound" {
  name        = "deny-all-prod-worker-inbound"
  network     = "default"
  description = "Deny all other inbound to workers"

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["prod-worker-ssh"]

  deny {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  priority = 100
}
