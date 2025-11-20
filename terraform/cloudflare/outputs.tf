output "api_fqdn" {
  value       = format("%s.%s", cloudflare_dns_record.api_a.name, data.cloudflare_zone.zone.name)
  description = "完整的 API 域名"
}

output "api_url" {
  value       = format("https://%s.%s/api/v1", cloudflare_dns_record.api_a.name, data.cloudflare_zone.zone.name)
  description = "API 基础 URL"
}

output "origin_ip" {
  value       = data.terraform_remote_state.gcp_vm.outputs.core_vm_ip
  description = "源服务器 IP (GCP VM)"
}

output "dns_record_id" {
  value       = cloudflare_dns_record.api_a.id
  description = "DNS 记录 ID"
}

output "cloudflare_proxied" {
  value       = cloudflare_dns_record.api_a.proxied
  description = "是否通过 Cloudflare 代理"
}


