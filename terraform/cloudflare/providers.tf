terraform {
  required_version = ">= 1.5.7"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }

  backend "gcs" {
    bucket = "tf-state-rural-neighbor-477211"
    prefix = "terraform/cloudflare"
  }
}

provider "cloudflare" {
  # 推荐用环境变量 CLOUDFLARE_API_TOKEN 提供，或使用 TF_VAR_api_token 传入 var.api_token
  api_token = var.api_token
}

# 读取 gcp-vm-hybrid 栈的核心 VM 出参（自动获取公网 IP）
data "terraform_remote_state" "gcp_vm" {
  backend = "gcs"
  config = {
    bucket = "tf-state-rural-neighbor-477211"
    prefix = "terraform/vm-hybrid"
  }
}



