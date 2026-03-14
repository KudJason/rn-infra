data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_address" "core_ip" {
  name   = "rn-core-ip"
  region = var.region
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
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common jq git

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

# Google Cloud CLI
curl -sS https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-ssh-init.sh | bash || true
export PATH=$PATH:/usr/local/bin

# Install Cloudflare Tunnel client (cloudflared) for rn-core-vm
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "安装 cloudflared..."
  ARCH="$(dpkg --print-architecture)"
  case "$${ARCH}" in
    amd64) CF_ARCH="amd64" ;;
    arm64) CF_ARCH="arm64" ;;
    *)
      echo "不支持的 cloudflared 架构: $${ARCH}，跳过安装"
      CF_ARCH=""
      ;;
  esac

  if [ -n "$${CF_ARCH}" ]; then
    CF_DEB="/tmp/cloudflared-$${CF_ARCH}.deb"
    if curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$${CF_ARCH}.deb" -o "$${CF_DEB}"; then
      if dpkg -i "$${CF_DEB}"; then
        echo "cloudflared 安装完成"
      else
        echo "dpkg 安装 cloudflared 失败，尝试修复依赖后重试"
        apt-get install -f -y && dpkg -i "$${CF_DEB}" || echo "cloudflared 安装失败，后续可手动安装"
      fi
      rm -f "$${CF_DEB}"
    else
      echo "cloudflared 下载失败，后续可手动安装"
    fi
  fi
else
  echo "cloudflared 已安装，跳过"
fi

# 挂载数据盘到 /data
mkfs.ext4 -F /dev/disk/by-id/google-rn-core-data-disk || true
mkdir -p /data
if ! grep -q "/data" /etc/fstab; then
  echo "/dev/disk/by-id/google-rn-core-data-disk /data ext4 defaults,nofail 0 2" >> /etc/fstab
fi
mount -a

# 安装 k3s
if [ ! -f /usr/local/bin/k3s ]; then
  echo "安装 k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --disable traefik --disable-cloud-controller' sh -
  sleep 10
  K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
  TOKEN_FILE=/tmp/k3s_cluster_token.txt
  printf "%s" "$K3S_TOKEN" > "$TOKEN_FILE"
  for i in $(seq 1 30); do
    if gcloud secrets versions add K3S_CLUSTER_TOKEN --data-file="$TOKEN_FILE" --project=${var.project_id}; then
      echo "K3S token 已发布到 Secret Manager"
      break
    fi
    echo "等待 Secret Manager 可用或权限生效... ($i/30)"
    sleep 10
  done
  rm -f "$TOKEN_FILE"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Ensure kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
  ln -s /usr/local/bin/k3s /usr/local/bin/kubectl || true
fi

# === 0. 等待 Worker 节点加入 (构建 K8s Pool) ===
echo "等待 Worker 节点加入..."
# 目标：1 Master + 1 Worker = 2 Nodes (MIG 配置为 1 个 worker)
TARGET_NODE_COUNT=2
MAX_WAIT_SECONDS=600
START_TIME=$(date +%s)

while true; do
  CURRENT_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
  echo "当前就绪节点数: $CURRENT_NODES / $TARGET_NODE_COUNT"
  
  if [ "$CURRENT_NODES" -ge "$TARGET_NODE_COUNT" ]; then
    echo "K8s Pool 构建完成！"
    break
  fi
  
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  if [ "$ELAPSED" -gt "$MAX_WAIT_SECONDS" ]; then
    echo "警告: 等待 Worker 节点超时 ($MAX_WAIT_SECONDS 秒)，当前节点数: $CURRENT_NODES。继续执行部署..."
    break
  fi
  
  sleep 10
done

# === 1. 配置 GHCR 凭据 ===
echo "配置 GHCR..."
SECRET_JSON=$(gcloud secrets versions access latest --secret="ghcr-ghcrio" --project="${var.project_id}")
GHCR_USER=$(echo "$SECRET_JSON" | jq -r .GHCR_USERNAME)
GHCR_TOKEN=$(echo "$SECRET_JSON" | jq -r .GHCR_TOKEN)

kubectl create namespace ruralneighbour-dev --dry-run=client -o yaml | kubectl apply -f -

kubectl delete secret ghcr-secret -n ruralneighbour-dev --ignore-not-found
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="$GHCR_USER" \
  --docker-password="$GHCR_TOKEN" \
  --docker-email="dev-null@local" \
  -n ruralneighbour-dev

# === 2. 拉取代码并部署 ===
echo "拉取代码..."
rm -rf /opt/ruralneighbour-k8s
# 注意：GHCR Token 需要有 Repo Contents Read 权限才能 clone 私有仓库
git clone https://$GHCR_USER:$GHCR_TOKEN@github.com/KudJason/ruralneighbour-k8s.git /opt/ruralneighbour-k8s

echo "部署服务..."
cd /opt/ruralneighbour-k8s
# 优先使用 kustomization
if [ -f "kustomization.yaml" ]; then
  kubectl apply -k .
elif [ -d "k8s" ]; then
  kubectl apply -k k8s
else
  kubectl apply -f . --recursive
fi

# === 3. 自动恢复备份 (如果数据库目录为空) ===
echo "检查备份..."
# 简单判断：如果 /data/postgres 为空 (假设 HostPath 挂载在此)，尝试恢复
# 注意：需确保 k8s yaml 中 postgres 挂载了 /data/postgres 到宿主机
if [ -z "$(ls -A /data/postgres 2>/dev/null)" ]; then
  echo "数据目录为空，检查 GCS 备份..."
  LATEST_PG_BACKUP=$(gsutil ls gs://${var.backup_bucket_name}/postgres/ | sort | tail -1 || true)
  
  if [ -n "$LATEST_PG_BACKUP" ]; then
    echo "发现备份: $LATEST_PG_BACKUP，等待数据库就绪..."
    kubectl wait --for=condition=ready pod -l app=postgres -n ruralneighbour-dev --timeout=300s || true
    
    PG_POD=$(kubectl get pod -n ruralneighbour-dev -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$PG_POD" ]; then
      echo "开始恢复到 $PG_POD ..."
      gsutil cp "$LATEST_PG_BACKUP" /tmp/restore.sql
      kubectl cp /tmp/restore.sql ruralneighbour-dev/$PG_POD:/tmp/restore.sql
      kubectl exec -n ruralneighbour-dev $PG_POD -- psql -U postgres -f /tmp/restore.sql || echo "恢复脚本执行可能有误，请检查日志"
      rm /tmp/restore.sql
      echo "恢复完成"
    fi
  else
    echo "未发现备份，跳过恢复。"
  fi
fi

echo "=== RuralNeighbour VM Ready ===" | tee /etc/motd
echo "数据目录: /data" | tee -a /etc/motd
echo "查看部署: sudo k3s kubectl get pods -n ruralneighbour-dev" | tee -a /etc/motd
echo "Cloudflare Tunnel 客户端版本: $(cloudflared --version 2>/dev/null | head -n 1 || echo 'not-installed')" | tee -a /etc/motd

# 简单备份脚本
cat >/usr/local/bin/rn_nightly_backup.sh <<'SHELL'
#!/bin/bash
set -euo pipefail
DATE=$(date +%F)
BK_DIR=/tmp/rn_bk_$DATE
mkdir -p "$BK_DIR"

# PostgreSQL 逻辑备份
if docker ps --format '{{.Names}}' | grep -q postgres; then
  # 注意：k3s 容器名可能不同，建议用 kubectl exec
  POD=$(kubectl get pod -n ruralneighbour-dev -l app=postgres -o jsonpath='{.items[0].metadata.name}' || true)
  if [ -n "$POD" ]; then
    kubectl exec -n ruralneighbour-dev $POD -- pg_dumpall -U postgres > "$BK_DIR/postgres-$DATE.sql"
  fi
fi

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
    access_config {
      nat_ip = google_compute_address.core_ip.address
    }
  }

  metadata = {
    startup-script         = local.core_startup
    enable-oslogin         = var.enable_oslogin ? "TRUE" : "FALSE"
    block-project-ssh-keys = "TRUE"
    "user-data"            = "rn"
    BACKUP_BUCKET          = var.backup_bucket_name
  }

  service_account {
    email = google_service_account.vm_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  tags = ["rn-core-ssh", "rn-core-web", "rn-core-vm"]

  depends_on = [
    google_project_service.enabled,
    google_storage_bucket.backup
  ]
}




