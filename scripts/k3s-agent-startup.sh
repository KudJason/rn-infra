#!/bin/bash
#
# K3s Agent 启动脚本
# 用于 spot VM 自动加入 K8s 集群
#
# 使用方法：
# 1. 将此脚本设置为 GCE VM 的 startup-script
# 2. 在 VM metadata 中设置以下变量：
#    - K3S_MASTER_IP: K3s master 节点的内网 IP
#    - K3S_TOKEN: K3s 集群 token (从 master 节点获取)

set -e

LOG_FILE="/var/log/k3s-agent-startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "K3s Agent 启动脚本"
echo "时间: $(date)"
echo "=========================================="

# 获取 metadata
K3S_MASTER_IP=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/k3s-master-ip" || echo "")

K3S_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/k3s-token" || echo "")

if [ -z "$K3S_MASTER_IP" ] || [ -z "$K3S_TOKEN" ]; then
  echo "❌ 错误: 未设置 K3s master IP 或 token"
  echo "请在 VM metadata 中设置 k3s-master-ip 和 k3s-token"
  exit 1
fi

echo "✓ K3s Master IP: $K3S_MASTER_IP"
echo "✓ K3s Token: ${K3S_TOKEN:0:20}..."

# 检查 K3s agent 是否已经安装
if systemctl is-active --quiet k3s-agent; then
  echo "✓ K3s agent 已经在运行"
  
  # 检查节点是否在集群中
  NODE_NAME=$(hostname)
  echo "检查节点 $NODE_NAME 是否在集群中..."
  
  exit 0
fi

# 检查是否已安装但未运行
if [ -f /usr/local/bin/k3s ]; then
  echo "✓ K3s 已安装，尝试启动服务..."
  systemctl start k3s-agent || {
    echo "⚠️ 启动失败，重新安装..."
    /usr/local/bin/k3s-agent-uninstall.sh || true
  }
fi

# 安装 K3s agent
if [ ! -f /usr/local/bin/k3s ] || ! systemctl is-active --quiet k3s-agent; then
  echo "📦 安装 K3s agent..."
  curl -sfL https://get.k3s.io | K3S_URL="https://${K3S_MASTER_IP}:6443" K3S_TOKEN="${K3S_TOKEN}" sh -
  
  echo "⏳ 等待 K3s agent 启动..."
  sleep 15
  
  if systemctl is-active --quiet k3s-agent; then
    echo "✅ K3s agent 安装并启动成功"
  else
    echo "❌ K3s agent 启动失败"
    systemctl status k3s-agent --no-pager
    exit 1
  fi
fi

echo "=========================================="
echo "K3s Agent 启动完成"
echo "时间: $(date)"
echo "=========================================="




















