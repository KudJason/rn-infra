#!/bin/bash
set -euo pipefail
LOG=/var/log/k3s-agent-startup.log
exec > >(tee -a "$LOG") 2>&1

echo "==== K3s Agent Startup (Secret Manager) $(date) ===="

META_BASE="http://metadata.google.internal/computeMetadata/v1"
H_FLAG="Metadata-Flavor: Google"

# Wait for metadata service to be ready
echo "Waiting for metadata service to be ready..."
for i in {1..60}; do
  if curl -sf -H "$H_FLAG" "$META_BASE/project/project-id" >/dev/null 2>&1; then
    echo "Metadata service is ready after $i attempts"
    break
  fi
  sleep 2
done

# Fetch master IP
echo "Fetching k3s-master-ip from metadata..."
MASTER_IP=""
for i in {1..15}; do
  MASTER_IP=$(curl -sf -H "$H_FLAG" "$META_BASE/instance/attributes/k3s-master-ip" 2>/dev/null | tr -d '\n' || true)
  [ -n "$MASTER_IP" ] && break
  sleep 2
done
if [ -z "$MASTER_IP" ]; then
  echo "ERROR: failed to get k3s-master-ip"; exit 1
fi
echo "Master IP: $MASTER_IP"

# Fetch project ID
echo "Fetching project ID..."
PROJECT_ID=$(curl -sf -H "$H_FLAG" "$META_BASE/project/project-id" 2>/dev/null | tr -d '\n')
echo "Project: $PROJECT_ID"

# Fetch access token with retries
echo "Fetching access token..."
ACCESS_TOKEN=""
for i in {1..30}; do
  RESP=$(curl -sf -H "$H_FLAG" "$META_BASE/instance/service-accounts/default/token" 2>/dev/null || true)
  ACCESS_TOKEN=$(echo "$RESP" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -n "$ACCESS_TOKEN" ]; then
    echo "Got access token (length: ${#ACCESS_TOKEN})"
    break
  fi
  sleep 2
done
if [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: failed to get access token after 30 retries"; exit 1
fi

# Fetch K3S token from Secret Manager
echo "Fetching K3S_CLUSTER_TOKEN from Secret Manager..."
SECRET_NAME="K3S_CLUSTER_TOKEN"
K3S_TOKEN=""
for i in {1..20}; do
  RESP=$(curl -sf -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://secretmanager.googleapis.com/v1/projects/$PROJECT_ID/secrets/$SECRET_NAME/versions/latest:access" 2>/dev/null || true)
  TOKEN_B64=$(echo "$RESP" | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -n "$TOKEN_B64" ]; then
    K3S_TOKEN=$(echo "$TOKEN_B64" | base64 -d 2>/dev/null || true)
    if [ -n "$K3S_TOKEN" ]; then
      echo "Got K3S token (length: ${#K3S_TOKEN})"
      break
    fi
  fi
  sleep 2
done
if [ -z "$K3S_TOKEN" ]; then
  echo "ERROR: failed to get K3S token from Secret Manager"; exit 1
fi

# Configure system
echo "Configuring kernel modules and sysctl..."
modprobe overlay || true
modprobe br_netfilter || true
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<SYSCTL
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL
sysctl --system >/dev/null 2>&1 || true

# Restart containerd
echo "Restarting containerd..."
systemctl restart containerd 2>/dev/null || true
sleep 3

# Uninstall old k3s agent if exists
if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
  echo "Uninstalling old k3s agent..."
  /usr/local/bin/k3s-agent-uninstall.sh || true
fi

# Install K3s agent
NODE_IP=$(hostname -I | awk '{print $1}')
NODE_NAME=$(hostname)
echo "Installing K3s agent (node: $NODE_NAME, IP: $NODE_IP)..."
export INSTALL_K3S_EXEC="agent --node-name $NODE_NAME --node-ip $NODE_IP"
curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" K3S_TOKEN="$K3S_TOKEN" sh -

# Enable and start k3s-agent
echo "Enabling and starting k3s-agent service..."
systemctl enable k3s-agent 2>/dev/null || true
systemctl restart k3s-agent || true
sleep 8

# Verify
if systemctl is-active --quiet k3s-agent; then
  echo "✅ k3s-agent is active and running"
else
  echo "❌ k3s-agent failed to start"
  journalctl -u k3s-agent --no-pager -n 30
  exit 1
fi

echo "==== K3s Agent Ready $(date) ===="
