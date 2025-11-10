resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
}

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

locals {
  startup = <<-EOT
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \n"\
  "$(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git

systemctl enable --now docker

echo "Docker installed: $(docker --version)"
echo "Compose installed: $(docker compose version || true)"

echo "=== NEXT STEPS ===" | tee /etc/motd
echo "1) 上传或克隆代码仓库到此机（例如 /opt/ruralneighbour）" | tee -a /etc/motd
echo "2) 运行: docker compose -f ms-backend/scripts/deployment/docker-compose.yaml up -d" | tee -a /etc/motd
EOT
}

resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interfaces {
    network = "default"
    access_config {}
  }

  metadata = {
    startup-script = local.startup
  }

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }

  tags = ["rn-backend", "allow-ssh", "allow-web"]

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "rn-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allow_source_ranges
  target_tags   = ["allow-ssh"]
}

resource "google_compute_firewall" "allow_web" {
  name    = "rn-allow-web"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = var.allow_source_ranges
  target_tags   = ["allow-web"]
}





