# Ingress Controller 配置说明

**日期**: 2026-03-15  
**状态**: ✅ 已修复 Terraform 配置

---

## 问题描述

之前的 Terraform 配置在安装 k3s 时禁用了 Traefik (`--disable traefik`)，但没有安装替代的 Ingress Controller（如 nginx），导致：
- 没有 Ingress Controller 在运行
- Cloudflare Tunnel 无法连接到后端服务
- `HTTP 502 Bad Gateway` 错误

---

## 解决方案

Terraform 配置已更新，支持两种 Ingress Controller：

### 1. Traefik（K3s 默认，推荐）

**优点**:
- K3s 内置，无需额外安装
- 资源占用更少
- 配置更简单

**配置**:
```hcl
variable "ingress_controller" {
  default = "traefik"
}
```

**Cloudflare Tunnel 配置**:
- URL: `http://127.0.0.1:80`
- Host Header: `api-dev.ruralneighbor.com`
- Path: 留空

### 2. nginx Ingress Controller

**优点**:
- 功能更丰富（如 CORS、重写规则）
- 社区支持更广泛
- 与现有 Ingress 配置兼容（`ingressClassName: nginx`）

**配置**:
```hcl
variable "ingress_controller" {
  default = "nginx"
}

variable "ingress_nodeport_http" {
  default = 30080
}

variable "ingress_nodeport_https" {
  default = 30443
}
```

**Cloudflare Tunnel 配置**:
- URL: `http://127.0.0.1:30080` (或自定义端口)
- Host Header: `api-dev.ruralneighbor.com`
- Path: 留空

---

## 使用方法

### 使用 Traefik（推荐）

1. **设置 Terraform 变量**:
   ```hcl
   # terraform.tfvars
   ingress_controller = "traefik"
   ```

2. **应用配置**:
   ```bash
   cd infra/terraform/gcp-vm-hybrid
   terraform apply
   ```

3. **更新 Ingress 配置**:
   如果使用 Traefik，需要修改 `ms-backend/k8s/_shared/ingress.yaml`:
   ```yaml
   spec:
     ingressClassName: traefik  # 从 nginx 改为 traefik
   ```

4. **配置 Cloudflare Tunnel**:
   - URL: `http://127.0.0.1:80`
   - Host Header: `api-dev.ruralneighbor.com`
   - Path: 留空

### 使用 nginx Ingress Controller

1. **设置 Terraform 变量**:
   ```hcl
   # terraform.tfvars
   ingress_controller = "nginx"
   ingress_nodeport_http = 30080
   ingress_nodeport_https = 30443
   ```

2. **应用配置**:
   ```bash
   cd infra/terraform/gcp-vm-hybrid
   terraform apply
   ```

3. **配置 Cloudflare Tunnel**:
   - URL: `http://127.0.0.1:30080`
   - Host Header: `api-dev.ruralneighbor.com`
   - Path: 留空

---

## 验证安装

### Traefik

```bash
# SSH 到 VM
gcloud compute ssh rn-core-vm --zone=us-central1-a

# 检查 Traefik Service
sudo k3s kubectl get svc -n kube-system traefik

# 检查 Traefik Pod
sudo k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# 测试本地连接
curl -H "Host: api-dev.ruralneighbor.com" http://127.0.0.1/health
```

### nginx Ingress Controller

```bash
# SSH 到 VM
gcloud compute ssh rn-core-vm --zone=us-central1-a

# 检查 nginx Ingress Controller Service
sudo k3s kubectl get svc -n ingress-nginx ingress-nginx-controller

# 检查 nginx Ingress Controller Pod
sudo k3s kubectl get pods -n ingress-nginx

# 测试本地连接
curl -H "Host: api-dev.ruralneighbor.com" http://127.0.0.1:30080/health
```

---

## 注意事项

1. **Ingress 配置兼容性**:
   - 如果使用 Traefik，需要修改 `ms-backend/k8s/_shared/ingress.yaml` 中的 `ingressClassName` 为 `traefik`
   - 如果使用 nginx，保持 `ingressClassName: nginx` 不变

2. **端口配置**:
   - Traefik 默认使用端口 80（HTTP）和 443（HTTPS）
   - nginx 使用 NodePort（默认 30080/30443），可在 Terraform 变量中自定义

3. **资源占用**:
   - Traefik: 更轻量，适合资源受限环境
   - nginx: 功能更丰富，但资源占用稍高

4. **迁移现有部署**:
   - 如果已有部署使用 nginx，建议继续使用 nginx
   - 如果是新部署，推荐使用 Traefik（更简单）

---

## 相关文件

- `infra/terraform/gcp-vm-hybrid/variables.tf` - Ingress Controller 变量定义
- `infra/terraform/gcp-vm-hybrid/on_demand_vm.tf` - 启动脚本中的 Ingress Controller 安装逻辑
- `ms-backend/k8s/_shared/ingress.yaml` - Ingress 资源配置

---

## 故障排除

### 问题：Ingress Controller 未运行

**检查**:
```bash
# Traefik
sudo k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# nginx
sudo k3s kubectl get pods -n ingress-nginx
```

**解决**:
- 检查 k3s 是否正常运行: `sudo systemctl status k3s`
- 查看 Pod 日志: `sudo k3s kubectl logs -n <namespace> <pod-name>`

### 问题：Cloudflare Tunnel 502 错误

**检查**:
1. Ingress Controller 是否运行（见上方）
2. Ingress 资源是否正确创建: `sudo k3s kubectl get ingress -n ruralneighbour-dev`
3. 本地连接测试: `curl -H "Host: api-dev.ruralneighbor.com" http://127.0.0.1:<port>/health`

**解决**:
- 确认 Cloudflare Tunnel 配置的 URL 和 Host Header 正确
- 确认 Ingress 资源的 `ingressClassName` 与安装的 Ingress Controller 匹配

---

**最后更新**: 2026-03-15
