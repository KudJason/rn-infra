data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# Production Static IP
resource "google_compute_address" "prod_core_ip" {
  name   = "rn-prod-core-ip"
  region = var.region
}

# Production Data Disk
resource "google_compute_disk" "prod_data" {
  name = "rn-prod-data-disk"
  type = "pd-standard"
  zone = var.zone
  size = var.prod_data_disk_size_gb
}

# Deterministic k3s join token (shared by server + worker agents)
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

locals {
  prod_core_startup = <<-EOT
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https jq git

# Mount data disk
mke2fs -F -t ext4 /dev/disk/by-id/google-rn-prod-data-disk || true
mkdir -p /data
if ! grep -q "/data" /etc/fstab; then
  echo "/dev/disk/by-id/google-rn-prod-data-disk /data ext4 defaults,nofail 0 2" >> /etc/fstab
fi
mount -a

# Install k3s server (single control-plane; worker agents join via MIG autoscaler)
if [ ! -f /usr/local/bin/k3s ]; then
  echo "Installing k3s server..."
  curl -sfL https://get.k3s.io | K3S_TOKEN='${random_password.k3s_token.result}' INSTALL_K3S_EXEC='server --disable-cloud-controller' sh -
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# Create the prod namespace (app deploy is handled manually after boot)
kubectl create namespace ruralneighbour-prod --dry-run=client -o yaml | kubectl apply -f -

echo "=== Production Core VM ready ==="
echo "kubectl get nodes"

EOT
}

# Production Core VM
resource "google_compute_instance" "prod_core" {
  name         = var.prod_on_demand_name
  machine_type = var.prod_machine_type
  zone         = var.zone

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = var.prod_boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  attached_disk {
    source = google_compute_disk.prod_data.id
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.prod_core_ip.address
    }
  }

  metadata = {
    startup-script = local.prod_core_startup
  }

  service_account {
    email  = google_service_account.prod_vm_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  tags = ["prod-core-ssh", "prod-core-web", "prod-core-vm"]
}
