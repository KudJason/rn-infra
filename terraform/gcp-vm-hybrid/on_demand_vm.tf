data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_disk" "data" {
  name = "rn-core-data-disk"
  type = "pd-standard"
  zone = var.zone
  size = var.data_disk_size_gb
}

locals {
  core_startup = <<-EOT
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common

# Docker
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \n"\
  "$(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git
systemctl enable --now docker

# Google Cloud CLI（用于备份到 GCS）
curl -sS https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-ssh-init.sh | bash || true
if ! command -v gcloud >/dev/null 2>&1; then
  echo "[WARN] gcloud 未安装，跳过 GCS 备份任务安装";
fi

# 挂载数据盘到 /data，并持久化到 fstab
mkfs.ext4 -F /dev/disk/by-id/google-rn-core-data-disk || true
mkdir -p /data
echo "/dev/disk/by-id/google-rn-core-data-disk /data ext4 defaults,nofail 0 2" >> /etc/fstab
mount -a

mkdir -p /opt/ruralneighbour
echo "=== NEXT STEPS ===" | tee /etc/motd
echo "1) 将代码放到 /opt/ruralneighbour" | tee -a /etc/motd
echo "2) 数据目录：/data（建议将 Postgres 数据映射到 /data/postgres）" | tee -a /etc/motd
echo "3) 可执行 docker compose -f ms-backend/scripts/deployment/docker-compose.yaml up -d" | tee -a /etc/motd

# 简单备份脚本（如 gcloud 可用则启用）
cat >/usr/local/bin/rn_nightly_backup.sh <<'SHELL'
#!/bin/bash
set -euo pipefail
DATE=$(date +%F)
BK_DIR=/tmp/rn_bk_$DATE
mkdir -p "$BK_DIR"

# PostgreSQL 逻辑备份（要求容器名为 postgres 或自定义）
if docker ps --format '{{.Names}}' | grep -q postgres; then
  docker exec postgres pg_dumpall -U devuser > "$BK_DIR/all.sql" || true
fi

# 打包 /data
tar -czf "$BK_DIR/data.tar.gz" /data || true

if command -v gcloud >/dev/null 2>&1; then
  gsutil cp -r "$BK_DIR" gs://${var.backup_bucket_name}/nightly/ || true
fi

rm -rf "$BK_DIR"
SHELL
chmod +x /usr/local/bin/rn_nightly_backup.sh

(crontab -l 2>/dev/null; echo "0 3 * * * BACKUP_BUCKET=${var.backup_bucket_name} /usr/local/bin/rn_nightly_backup.sh >/var/log/rn_nightly_backup.log 2>&1") | crontab -

EOT
}

resource "google_compute_instance" "core" {
  name         = var.on_demand_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  attached_disk {
    source = google_compute_disk.data.id
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    startup-script             = local.core_startup
    enable-oslogin             = var.enable_oslogin ? "TRUE" : "FALSE"
    block-project-ssh-keys     = "TRUE"
    "user-data"               = "rn"
    BACKUP_BUCKET              = var.backup_bucket_name
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  tags = ["rn-core-ssh", "rn-core-web"]

  depends_on = [
    google_project_service.enabled,
    google_storage_bucket.backup
  ]
}




