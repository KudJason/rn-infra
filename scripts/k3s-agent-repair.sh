#!/bin/bash
set -euo pipefail
LOG=/var/log/k3s-agent-repair.log
exec > >(tee -a "$LOG") 2>&1

METADATA="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
H="-H Metadata-Flavor: Google"
MASTER_IP=$(curl -s $H "$METADATA/k3s-master-ip" || true)
TOKEN=$(curl -s $H "$METADATA/k3s-token" || true)
NODE_IP=$(hostname -I | awk '{print $1}')
NODE_NAME=$(hostname)

modprobe overlay || true
modprobe br_netfilter || true
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<SYS
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYS
sysctl --system || true

if command -v ufw >/dev/null 2>&1; then
  ufw disable || true
fi

systemctl restart containerd || true
sleep 3

if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
  /usr/local/bin/k3s-agent-uninstall.sh || true
fi
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="agent --node-name $NODE_NAME --node-ip $NODE_IP" \
  K3S_URL="https://$MASTER_IP:6443" \
  K3S_TOKEN="$TOKEN" sh -

systemctl enable k3s-agent || true
systemctl restart k3s-agent || true
sleep 8
systemctl is-active k3s-agent || (echo "k3s-agent not active"; exit 1)
