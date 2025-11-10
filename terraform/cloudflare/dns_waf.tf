locals {
  origin_ip = data.terraform_remote_state.gcp_vm.outputs.core_vm_ip
}

# 读取 zone 详情用于输出 FQDN 计算
data "cloudflare_zone" "zone" {
  zone_id = var.zone_id
}

# DNS A 记录 - API 入口
resource "cloudflare_dns_record" "api_a" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"
  content = local.origin_ip
  proxied = true
  ttl     = 1 # Auto
  comment = "API Gateway - points to GCP VM"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 注意事项
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
# 以下配置需要在 Cloudflare Dashboard 中手动设置：
#
# 1. SSL/TLS 设置:
#    - SSL 模式: Flexible
#    - 最低 TLS: 1.2
#    - 强制 HTTPS: 开启
#    - HSTS: 建议启用
#
# 2. 速率限制:
#    - Security → WAF → Rate limiting rules
#    - 可选配置 100 请求/分钟
#
# 3. 页面规则:
#    - Rules → Page Rules
#    - api.ruralneighbor.com/api/v1/* → Cache Level: Bypass
#
# 4. 防火墙规则:
#    - Security → WAF → Firewall rules
#    - 根据需要配置
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


