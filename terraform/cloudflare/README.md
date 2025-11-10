# Cloudflare API Gateway (Terraform)

使用 Terraform 管理 Cloudflare，为 RuralNeighbour 配置统一 API 入口。

## 功能

### DNS 配置
- 自动读取 GCP VM 公网 IP（通过 remote_state）
- 创建 `api.ruralneighbor.com` A 记录
- 启用 Cloudflare 代理（橙云）

### SSL/TLS 安全
- **SSL 模式**: Flexible（Cloudflare 到客户端加密）
- **最低 TLS**: 1.2
- **强制 HTTPS**: 是
- **HTTP/2 & HTTP/3**: 已启用
- **自动 HTTPS 重写**: 是

### 性能优化
- Brotli 压缩
- API 请求不缓存（动态内容）
- 健康检查端点短暂缓存（60秒）

### 安全防护
- **速率限制**: 100 请求/分钟（当前为 simulate 模式）
- **安全等级**: Medium
- **安全头**: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection

## 架构

```
Internet (HTTPS)
    ↓
Cloudflare CDN (SSL Termination)
    ↓
api.ruralneighbor.com (HTTP)
    ↓
GCP VM (Nginx API Gateway)
    ├─ /api/v1/auth → Auth Service (8002)
    ├─ /api/v1/users → User Service (8003)
    ├─ /api/v1/requests → Request Service (8001)
    ├─ /api/v1/payments → Payment Service (8005)
    ├─ /api/v1/notifications → Notification Service (8006)
    └─ /api/v1/locations → Location Service (8004)
```

## 前置条件

### 1. GCP VM 已部署
确保 `gcp-vm-hybrid` Terraform 栈已部署，并且 VM 公网 IP 可用。

### 2. Cloudflare 账户信息
- **Zone ID**: 你的域名 Zone ID
- **Account ID**: Cloudflare 账户 ID  
- **API Token**: 需要以下权限：
  - `Zone:DNS:Edit`
  - `Zone:Zone Settings:Edit`
  - `Zone:Page Rules:Edit`

获取方式：
1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
2. 选择你的域名
3. 在右侧查看 Zone ID 和 Account ID
4. 创建 API Token: My Profile → API Tokens → Create Token

### 3. Nginx API Gateway
在 VM 上安装 Nginx（部署脚本会自动执行）。

## 部署步骤

### 步骤 1: 设置 Nginx API 网关

首先在 VM 上部署 Nginx：

```bash
cd /path/to/ruralneighbour
./scripts/deployment/setup-nginx-gateway.sh
```

验证 Nginx：
```bash
# 通过 SSH 测试
gcloud compute ssh rn-core-vm --zone=us-east4-a --command="curl -s http://localhost/health"
```

### 步骤 2: 初始化 Terraform

```bash
cd infra/terraform/cloudflare
export CLOUDFLARE_API_TOKEN=your_cloudflare_api_token
terraform init
```

### 步骤 3: 规划部署

```bash
terraform plan
```

检查将要创建的资源：
- DNS A 记录
- SSL/TLS 设置
- 速率限制规则
- 页面规则

### 步骤 4: 应用配置

```bash
terraform apply
```

确认后输入 `yes`。

### 步骤 5: 验证部署

```bash
# 检查 DNS 解析（可能需要等待几分钟）
dig api.ruralneighbor.com

# 测试 API 端点
curl https://api.ruralneighbor.com/health
curl https://api.ruralneighbor.com/api/v1/auth/health
```

## 输出

Terraform 会输出以下信息：

```hcl
api_fqdn              = "api.ruralneighbor.com"
api_url               = "https://api.ruralneighbor.com/api/v1"
origin_ip             = "34.48.255.154"
dns_record_id         = "..."
cloudflare_proxied    = true
```

## API 端点

部署完成后，可以通过以下端点访问：

### 健康检查
- `https://api.ruralneighbor.com/health` - 网关健康检查
- `https://api.ruralneighbor.com/health/auth` - Auth 服务健康检查
- `https://api.ruralneighbor.com/health/user` - User 服务健康检查
- `https://api.ruralneighbor.com/health/request` - Request 服务健康检查

### API 服务
- `https://api.ruralneighbor.com/api/v1/auth/*` - 认证服务
- `https://api.ruralneighbor.com/api/v1/users/*` - 用户服务
- `https://api.ruralneighbor.com/api/v1/requests/*` - 请求服务
- `https://api.ruralneighbor.com/api/v1/payments/*` - 支付服务
- `https://api.ruralneighbor.com/api/v1/notifications/*` - 通知服务
- `https://api.ruralneighbor.com/api/v1/locations/*` - 位置服务

## 配置文件

- `dns_waf.tf` - DNS、SSL/TLS、安全规则配置
- `providers.tf` - Provider 和 backend 配置
- `variables.tf` - 变量定义
- `outputs.tf` - 输出定义
- `cloudflare.auto.tfvars` - 自动加载的变量值

## 自定义配置

### 修改速率限制
编辑 `dns_waf.tf` 中的 `cloudflare_rate_limit` 资源：

```hcl
threshold = 200  # 改为 200 请求/分钟
period    = 60
action {
  mode    = "ban"  # 从 simulate 改为 ban（启用封禁）
  timeout = 300    # 封禁 5 分钟
}
```

### 升级到 Full (Strict) SSL
当 VM 上配置了有效 SSL 证书后：

```hcl
settings {
  ssl = "full"  # 或 "strict"
}
```

### 添加更多安全规则
可以添加 WAF 规则、IP 白名单等：

```hcl
resource "cloudflare_firewall_rule" "block_bad_bots" {
  zone_id = var.zone_id
  # ... 配置
}
```

## 故障排除

### DNS 未解析
```bash
# 检查 DNS 记录
dig api.ruralneighbor.com @1.1.1.1

# 等待 DNS 传播（可能需要 1-5 分钟）
```

### 502 Bad Gateway
- 检查 Nginx 是否运行: `sudo systemctl status nginx`
- 检查后端服务是否运行: `docker-compose ps`
- 查看 Nginx 日志: `sudo tail -f /var/log/nginx/api_gateway_error.log`

### SSL 证书错误
- 确认 Cloudflare SSL 模式设置为 Flexible
- 检查 Cloudflare 仪表板中的 SSL/TLS 设置

## 成本

Cloudflare 免费版包含：
- ✅ DNS 管理
- ✅ CDN 和代理
- ✅ 基础 SSL 证书
- ✅ 基础 DDoS 防护
- ✅ 3 条页面规则
- ⚠️ 速率限制（有限）
- ⚠️ WAF 规则（有限）

**估算成本**: $0/月（使用免费版）

## 维护

### 更新配置
```bash
terraform plan
terraform apply
```

### 查看当前状态
```bash
terraform show
```

### 销毁资源（谨慎！）
```bash
terraform destroy
```

## 参考文档

- [Cloudflare Terraform Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Nginx Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)



