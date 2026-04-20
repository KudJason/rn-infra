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
  case "$$${ARCH}" in
    amd64) CF_ARCH="amd64" ;;
    arm64) CF_ARCH="arm64" ;;
    *)
      echo "不支持的 cloudflared 架构: $$${ARCH}，跳过安装"
      CF_ARCH=""
      ;;
  esac

  if [ -n "$$${CF_ARCH}" ]; then
    CF_DEB="/tmp/cloudflared-$$${CF_ARCH}.deb"
    if curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$$${CF_ARCH}.deb" -o "$$${CF_DEB}"; then
      if dpkg -i "$$${CF_DEB}"; then
        echo "cloudflared 安装完成"
      else
        echo "dpkg 安装 cloudflared 失败，尝试修复依赖后重试"
        apt-get install -f -y && dpkg -i "$$${CF_DEB}" || echo "cloudflared 安装失败，后续可手动安装"
      fi
      rm -f "$$${CF_DEB}"
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
  # 根据 ingress_controller 变量决定是否禁用 Traefik
  if [ "${var.ingress_controller}" = "traefik" ]; then
    echo "使用 Traefik Ingress Controller (K3s 默认)"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --disable-cloud-controller' sh -
  else
    echo "禁用 Traefik，将安装 nginx Ingress Controller"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --disable traefik --disable-cloud-controller' sh -
  fi
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
# 从 metadata 获取 token（terraform 变量注入）
GHCR_TOKEN="$$${GHCR_TOKEN:-}"
if [ -z "$GHCR_TOKEN" ]; then
  echo "ERROR: GHCR_TOKEN is empty. Please set var.ghcr_token in terraform."
  exit 1
fi

# 安装 gh CLI（用于 docker login ghcr.io）
if ! command -v gh >/dev/null 2>&1; then
  echo "安装 gh CLI..."
  ARCH="$(dpkg --print-architecture)"
  case "$$${ARCH}" in
    amd64) GH_ARCH="linux_amd64" ;;
    arm64) GH_ARCH="linux_arm64" ;;
    *)
      echo "不支持的 gh 架构: $$${ARCH}"
      GH_ARCH=""
      ;;
  esac
  if [ -n "$GH_ARCH" ]; then
    GH_TAR="/tmp/gh.tar.gz"
    curl -fsSL "https://github.com/cli/cli/releases/download/v2.63.0/gh_2.63.0_$$${GH_ARCH}.tar.gz" -o "$GH_TAR"
    tar -xzf "$GH_TAR" -C /tmp
    mv /tmp/gh_2.63.0_$$${GH_ARCH}/bin/gh /usr/local/bin/gh
    rm -rf "$GH_TAR" /tmp/gh_2.63.0_$$${GH_ARCH}
    echo "gh CLI 安装完成"
  fi
fi

# gh auth login（使用 token）
if gh auth status 2>/dev/null | grep -q "github.com"; then
  echo "gh 已登录，跳过"
else
  echo "$GHCR_TOKEN" | gh auth login --hostname github.com --with-token
fi

# docker login ghcr.io（使用 gh token，gh CLI 已登录）
GHCR_USER="KudJason"  # ghcr.io 用户名固定
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# Create both dev and prod namespaces
kubectl create namespace ruralneighbour-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ruralneighbour-prod --dry-run=client -o yaml | kubectl apply -f -

# GHCR secret for dev namespace（用于 k8s 拉取 ghcr.io 镜像）
kubectl delete secret ghcr-secret -n ruralneighbour-dev --ignore-not-found
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="$${GHCR_USER:-KudJason}" \
  --docker-password="$GHCR_TOKEN" \
  --docker-email="dev-null@local" \
  -n ruralneighbour-dev

# GHCR secret for prod namespace
kubectl delete secret ghcr-secret -n ruralneighbour-prod --ignore-not-found
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="$${GHCR_USER:-KudJason}" \
  --docker-password="$GHCR_TOKEN" \
  --docker-email="dev-null@local" \
  -n ruralneighbour-prod

# === 1.5 安装 Ingress Controller (如果使用 nginx) ===
if [ "${var.ingress_controller}" = "nginx" ]; then
  echo "安装 nginx Ingress Controller..."
  
  # 安装 Helm (如果不存在)
  if ! command -v helm >/dev/null 2>&1; then
    echo "安装 Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  
  # 等待 k3s 完全就绪
  echo "等待 k3s 就绪..."
  for i in $(seq 1 30); do
    if kubectl get nodes >/dev/null 2>&1; then
      echo "k3s 就绪"
      break
    fi
    echo "等待 k3s... ($i/30)"
    sleep 2
  done
  
  # 安装 nginx Ingress Controller
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
  helm repo update
  
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=${var.ingress_nodeport_http} \
    --set controller.service.nodePorts.https=${var.ingress_nodeport_https} \
    --set controller.admissionWebhooks.enabled=false \
    --wait --timeout=5m || echo "⚠️  Ingress Controller 安装可能需要更长时间，继续部署..."
  
  echo "✅ nginx Ingress Controller 安装完成 (NodePort: ${var.ingress_nodeport_http})"
else
  echo "使用 Traefik Ingress Controller (K3s 默认)"
  # Traefik 默认在端口 80 和 443 上运行（通过 LoadBalancer Service）
  # 检查 Traefik Service
  echo "检查 Traefik Service..."
  kubectl get svc -n kube-system traefik -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Traefik Service 可能尚未就绪"
fi

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

# === 4. 输出 Ingress Controller 信息 ===
echo ""
echo "=== Ingress Controller 信息 ==="
if [ "${var.ingress_controller}" = "nginx" ]; then
  INGRESS_PORT=${var.ingress_nodeport_http}
  echo "Ingress Controller: nginx"
  echo "NodePort (HTTP): $INGRESS_PORT"
  echo "NodePort (HTTPS): ${var.ingress_nodeport_https}"
  echo ""
  echo "Cloudflare Tunnel 应配置为: http://127.0.0.1:$INGRESS_PORT"
  kubectl get svc -n ingress-nginx ingress-nginx-controller || echo "⚠️  Ingress Controller Service 可能尚未就绪"
else
  echo "Ingress Controller: Traefik (K3s 默认)"
  echo "Traefik 默认在端口 80 上运行"
  echo ""
  echo "Cloudflare Tunnel 应配置为: http://127.0.0.1:80"
  kubectl get svc -n kube-system traefik || echo "⚠️  Traefik Service 可能尚未就绪"
fi

echo "=== RuralNeighbour VM Ready ===" | tee /etc/motd
echo "数据目录: /data" | tee -a /etc/motd
echo "查看部署: sudo k3s kubectl get pods -n ruralneighbour-dev" | tee -a /etc/motd
echo "Ingress Controller: ${var.ingress_controller}" | tee -a /etc/motd
if [ "${var.ingress_controller}" = "nginx" ]; then
  echo "Ingress NodePort: ${var.ingress_nodeport_http}" | tee -a /etc/motd
fi
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
    GHCR_TOKEN             = var.ghcr_token
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




