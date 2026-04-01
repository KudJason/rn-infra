data "google_compute_image" "debian_prod" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_address" "prod_core_ip" {
  name   = "rn-prod-core-ip"
  region = var.region
}

resource "google_compute_disk" "prod_data" {
  name = "rn-prod-data-disk"
  type = "pd-standard"
  zone = var.zone
  size = var.prod_data_disk_size_gb
}

locals {
  prod_core_startup = <<-EOT
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

# Install Cloudflare Tunnel client (cloudflared) for prod core VM
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "Installing cloudflared..."
  ARCH="$(dpkg --print-architecture)"
  case "$${ARCH}" in
    amd64) CF_ARCH="amd64" ;;
    arm64) CF_ARCH="arm64" ;;
    *)
      echo "Unsupported architecture for cloudflared: $${ARCH}, skipping"
      CF_ARCH=""
      ;;
  esac

  if [ -n "$${CF_ARCH}" ]; then
    CF_DEB="/tmp/cloudflared-$${ARCH}.deb"
    if curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$${CF_ARCH}.deb" -o "$${CF_DEB}"; then
      if dpkg -i "$${CF_DEB}"; then
        echo "cloudflared installed"
      else
        echo "dpkg install cloudflared failed, trying to fix dependencies"
        apt-get install -f -y && dpkg -i "$${CF_DEB}" || echo "cloudflared install failed"
      fi
      rm -f "$${CF_DEB}"
    else
      echo "cloudflared download failed"
    fi
  fi
else
  echo "cloudflared already installed, skipping"
fi

# Mount data disk to /data
mke2fs -F -t ext4 /dev/disk/by-id/google-rn-prod-data-disk || true
mkdir -p /data
if ! grep -q "/data" /etc/fstab; then
  echo "/dev/disk/by-id/google-rn-prod-data-disk /data ext4 defaults,nofail 0 2" >> /etc/fstab
fi
mount -a

# Install k3s
if [ ! -f /usr/local/bin/k3s ]; then
  echo "Installing k3s..."
  if [ "${var.ingress_controller}" = "traefik" ]; then
    echo "Using Traefik Ingress Controller (K3s default)"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --disable-cloud-controller' sh -
  else
    echo "Disabling Traefik, will install nginx Ingress Controller"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --disable traefik --disable-cloud-controller' sh -
  fi
  sleep 10
  K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
  TOKEN_FILE=/tmp/k3s_cluster_token_prod.txt
  printf "%s" "$K3S_TOKEN" > "$TOKEN_FILE"
  for i in $(seq 1 30); do
    if gcloud secrets versions add K3S_CLUSTER_TOKEN_PROD --data-file="$TOKEN_FILE" --project=${var.project_id}; then
      echo "K3S PROD token published to Secret Manager"
      break
    fi
    echo "Waiting for Secret Manager... ($i/30)"
    sleep 10
  done
  rm -f "$TOKEN_FILE"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if ! command -v kubectl >/dev/null 2>&1; then
  ln -s /usr/local/bin/k3s /usr/local/bin/kubectl || true
fi

# === Wait for Worker nodes ===
echo "Waiting for Worker nodes to join..."
TARGET_NODE_COUNT=${var.prod_target_node_count}
MAX_WAIT_SECONDS=600
START_TIME=$(date +%s)

while true; do
  CURRENT_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
  echo "Current ready nodes: $CURRENT_NODES / $TARGET_NODE_COUNT"

  if [ "$CURRENT_NODES" -ge "$TARGET_NODE_COUNT" ]; then
    echo "K8s Pool build complete!"
    break
  fi

  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  if [ "$ELAPSED" -gt "$MAX_WAIT_SECONDS" ]; then
    echo "Warning: Wait for Worker nodes timed out ($MAX_WAIT_SECONDS seconds), current nodes: $CURRENT_NODES. Continuing..."
    break
  fi

  sleep 10
done

# === Configure GHCR credentials ===
echo "Configuring GHCR..."
SECRET_JSON=$(gcloud secrets versions access latest --secret="ghcr-ghcrio" --project="${var.project_id}")
GHCR_USER=$(echo "$SECRET_JSON" | jq -r .GHCR_USERNAME)
GHCR_TOKEN=$(echo "$SECRET_JSON" | jq -r .GHCR_TOKEN)

# Create prod namespace
kubectl create namespace ruralneighbour-prod --dry-run=client -o yaml | kubectl apply -f -

# GHCR secret for prod namespace
kubectl delete secret ghcr-secret -n ruralneighbour-prod --ignore-not-found
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="$GHCR_USER" \
  --docker-password="$GHCR_TOKEN" \
  --docker-email="dev-null@local" \
  -n ruralneighbour-prod

# === Ingress Controller ===
if [ "${var.ingress_controller}" = "nginx" ]; then
  echo "Installing nginx Ingress Controller..."

  if ! command -v helm >/dev/null 2>&1; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  echo "Waiting for k3s..."
  for i in $(seq 1 30); do
    if kubectl get nodes >/dev/null 2>&1; then
      echo "k3s ready"
      break
    fi
    echo "Waiting for k3s... ($i/30)"
    sleep 2
  done

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
  helm repo update

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=${var.ingress_nodeport_http} \
    --set controller.service.nodePorts.https=${var.ingress_nodeport_https} \
    --set controller.admissionWebhooks.enabled=false \
    --wait --timeout=5m || echo "Ingress Controller installation may take longer, continuing..."

  echo "nginx Ingress Controller installed (NodePort: ${var.ingress_nodeport_http})"
else
  echo "Using Traefik Ingress Controller (K3s default)"
  echo "Checking Traefik Service..."
  kubectl get svc -n kube-system traefik -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Traefik Service may not be ready yet"
fi

# === Clone and deploy ===
echo "Cloning code..."
rm -rf /opt/ruralneighbour-k8s
git clone https://$GHCR_USER:$GHCR_TOKEN@github.com/KudJason/ruralneighbour-k8s.git /opt/ruralneighbour-k8s

echo "Deploying services..."
cd /opt/ruralneighbour-k8s
if [ -f "kustomization.yaml" ]; then
  kubectl apply -k .
elif [ -d "k8s" ]; then
  kubectl apply -k k8s
else
  kubectl apply -f . --recursive
fi

# === Backup script ===
cat >/usr/local/bin/rn_prod_nightly_backup.sh <<'SHELL'
#!/bin/bash
set -euo pipefail
DATE=$(date +%F)
BK_DIR=/tmp/rn_prod_bk_$DATE
mkdir -p "$BK_DIR"

if docker ps --format '{{.Names}}' | grep -q postgres; then
  POD=$(kubectl get pod -n ruralneighbour-prod -l app=postgis-pg-prod -o jsonpath='{.items[0].metadata.name}' || true)
  if [ -n "$POD" ]; then
    kubectl exec -n ruralneighbour-prod $POD -- pg_dumpall -U postgres > "$BK_DIR/postgres-$DATE.sql"
  fi
fi

if command -v gcloud >/dev/null 2>&1; then
  gsutil cp -r "$BK_DIR" gs://${var.prod_backup_bucket_name}/nightly/ || true
fi
rm -rf "$BK_DIR"
SHELL
chmod +x /usr/local/bin/rn_prod_nightly_backup.sh

(crontab -l 2>/dev/null; echo "0 3 * * * BACKUP_BUCKET=${var.prod_backup_bucket_name} /usr/local/bin/rn_prod_nightly_backup.sh > /var/log/rn_prod_backup.log 2>&1") | crontab -

echo "=== Production VM Ready ===" | tee /etc/motd
echo "Data directory: /data" | tee -a /etc/motd
echo "View deployment: sudo k3s kubectl get pods -n ruralneighbour-prod" | tee -a /etc/motd
echo "Ingress Controller: ${var.ingress_controller}" | tee -a /etc/motd
if [ "${var.ingress_controller}" = "nginx" ]; then
  echo "Ingress NodePort: ${var.ingress_nodeport_http}" | tee -a /etc/motd
fi

EOT
}

resource "google_compute_instance" "prod_core" {
  name         = var.prod_on_demand_name
  machine_type = var.prod_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_prod.self_link
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
    startup-script         = local.prod_core_startup
    enable-oslogin         = var.enable_oslogin ? "TRUE" : "FALSE"
    block-project-ssh-keys = "TRUE"
    "user-data"            = "rn-prod"
    BACKUP_BUCKET          = var.prod_backup_bucket_name
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

  tags = ["prod-core-ssh", "prod-core-web", "prod-core-vm"]

  depends_on = [
    google_project_service.enabled
  ]
}
