resource "google_compute_instance_template" "spot_tmpl" {
  name_prefix  = "rn-spot-tmpl-"
  machine_type = var.machine_type

  disk {
    source_image = data.google_compute_image.debian.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = "pd-standard"
  }

  network_interface {
    network = "default"
    access_config {}
  }

  tags = ["rn-mig"]

  metadata = {
    startup-script         = <<-EOT
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common

# Install Docker
install -d -m 0755 /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes --batch -o /etc/apt/keyrings/docker.gpg
fi
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Install gcloud (if not present)
if ! command -v gcloud >/dev/null 2>&1; then
    # Attempt to install via apt if possible, or use the script
    apt-get install -y google-cloud-cli || true
fi

# Fetch K3s Token
# Retry loop for secret fetching
MAX_RETRIES=20
for i in $(seq 1 $MAX_RETRIES); do
    K3S_TOKEN=$(gcloud secrets versions access latest --secret=K3S_CLUSTER_TOKEN --project=rural-neighbor-477211 2>/dev/null) && break
    echo "Waiting for secret access... ($i/$MAX_RETRIES)"
    sleep 10
done

if [ -z "$K3S_TOKEN" ]; then
    echo "Failed to fetch K3S_TOKEN"
    exit 1
fi

MASTER_IP="10.150.0.41"

# Install K3s Agent
curl -sfL https://get.k3s.io | K3S_URL=https://$${MASTER_IP}:6443 K3S_TOKEN=$${K3S_TOKEN} sh -

echo "Spot worker ready and joined cluster"
EOT
    enable-oslogin         = var.enable_oslogin ? "TRUE" : "FALSE"
    block-project-ssh-keys = "TRUE"
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  scheduling {
    provisioning_model         = "STANDARD"
    automatic_restart          = true
    on_host_maintenance        = "MIGRATE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "spot_mig" {
  name               = "rn-spot-mig"
  base_instance_name = "rn-spot"
  zone               = var.zone
  target_size        = var.mig_size

  version {
    instance_template = google_compute_instance_template.spot_tmpl.self_link
  }
}





