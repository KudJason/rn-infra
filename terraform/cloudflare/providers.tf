terraform {
  required_version = ">= 1.5.7"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }

  backend "gcs" {
    bucket = "tf-state-rural-neighbor-1"
    prefix = "terraform/cloudflare"
  }
}

provider "cloudflare" {
  # Cloudflare provider 会自动查找 CLOUDFLARE_API_TOKEN 环境变量
  # 如果设置了 var.api_token，则使用变量值；否则使用环境变量
  api_token = try(var.api_token, null)
}

# 读取 gcp-vm-hybrid 栈的核心 VM 出参（自动获取公网 IP）
data "terraform_remote_state" "gcp_vm" {
  backend = "gcs"
  config = {
    bucket = "tf-state-rural-neighbor-1"
    prefix = "terraform/vm-hybrid"
  }
}



