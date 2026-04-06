data "google_compute_image" "debian_worker" {
  family  = "debian-12"
  project = "debian-cloud"
}

locals {
  prod_worker_startup = <<-EOT
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Stop PackageKit to avoid blocking apt-get
systemctl stop packagekit || true
systemctl mask packagekit || true

apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common jq

# Docker
install -d -m 0755 /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes --batch -o /etc/apt/keyrings/docker.gpg
fi
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# K3s token - embedded directly (use single $ since $$ in terraform heredoc becomes $)
K3S_TOKEN='K10fe8bcb7c881265f31d266bcc5004efb87ee7bb77d71cfe62786004eacf59c141::server:42d0428c0a65289cd716bf9cdcb127c6'

# Wait for k3s API
# Use internal IP directly - core VM is at 10.128.0.12 in us-central1
MASTER_IP="10.128.0.12"
MAX_WAIT=300
START_TIME=$(date +%s)
while true; do
  # Use /ping endpoint which returns "pong" without authentication
  if curl -sk "https://$${MASTER_IP}:6443/ping" 2>/dev/null | grep -q "pong"; then
    echo "K3s API is ready"
    break
  fi
  [ $(( $(date +%s) - START_TIME )) -gt $MAX_WAIT ] && { echo "Timeout waiting for k3s"; exit 1; }
  sleep 5
done

# Install k3s agent using internal IP
export K3S_URL="https://$${MASTER_IP}:6443"
export K3S_TOKEN='K10fe8bcb7c881265f31d266bcc5004efb87ee7bb77d71cfe62786004eacf59c141::server:42d0428c0a65289cd716bf9cdcb127c6'
curl -sfL https://get.k3s.io | sh -s - agent --node-name "$(hostname)"

EOT
}

resource "google_compute_instance_template" "prod_worker_v6" {
  name = "rn-prod-worker-template-v6"

  machine_type = var.prod_worker_machine_type

  disk {
    boot         = true
    auto_delete  = true
    disk_size_gb = var.prod_worker_disk_size_gb
    source_image = data.google_compute_image.debian_worker.self_link
    disk_type    = "pd-standard"
  }

  network_interface {
    network = "default"
  }

  metadata = {
    startup-script = local.prod_worker_startup
  }

  service_account {
    email = "default"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  tags = ["prod-worker-ssh", "prod-worker-internal"]
}

resource "google_compute_region_instance_group_manager" "prod_workers_v6" {
  name = "rn-prod-workers-igm-v6"

  base_instance_name = "rn-prod-worker"
  region              = var.region

  version {
    instance_template = google_compute_instance_template.prod_worker_v6.id
  }

  target_size = var.prod_mig_size

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed      = 0
    max_unavailable_fixed = 3
    replacement_method    = "RECREATE"
  }
}

resource "google_compute_health_check" "prod_worker" {
  name = "rn-prod-worker-hc"

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 22
  }
}

resource "google_compute_region_autoscaler" "prod_workers_v6" {
  name   = "rn-prod-workers-autoscaler-v6"
  target = google_compute_region_instance_group_manager.prod_workers_v6.id
  region = var.region

  autoscaling_policy {
    min_replicas       = 2
    max_replicas       = 5
    cooldown_period    = 60
    cpu_utilization {
      target = 0.6
    }
  }
}
