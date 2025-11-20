variable "api_token" {
  description = "Cloudflare API Token (建议用环境变量 CLOUDFLARE_API_TOKEN 或 TF_VAR_api_token 注入)"
  type        = string
  default     = null
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare Zone ID（你的域名所属 Zone）"
  type        = string
}

variable "account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "record_name" {
  description = "要创建的 A 记录主机名（例如 api）"
  type        = string
  default     = "api"
}

variable "domain_name" {
  description = "域名（例如 ruralneighbor.com）"
  type        = string
  default     = "ruralneighbor.com"
}



