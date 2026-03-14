resource "google_compute_firewall" "allow_on_demand_ssh" {
  name     = "rn-allow-ssh-core"
  network  = "default"
  priority = 900

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = var.admin_ip_ranges
  target_tags   = ["rn-core-ssh", "rn-mig"]
}

resource "google_compute_firewall" "allow_on_demand_web" {
  name    = "rn-allow-web-core"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = var.cloudflare_ipv4_ranges
  target_tags   = ["rn-core-web"]
}

resource "google_compute_firewall" "deny_all_mig_inbound" {
  name    = "rn-deny-mig-inbound"
  network = "default"

  deny { protocol = "all" }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["rn-mig"]
  priority      = 1000
  direction     = "INGRESS"
}

resource "google_compute_firewall" "allow_cluster_internal" {
  name     = "rn-allow-cluster-internal"
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

  source_tags = ["rn-core-vm", "rn-mig"]
  target_tags = ["rn-core-vm", "rn-mig"]
}


