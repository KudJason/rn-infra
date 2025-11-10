variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "rural-neighbor-477211"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east4"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-east4-a"
}

variable "on_demand_name" {
  description = "On-demand VM name"
  type        = string
  default     = "rn-core-vm"
}

variable "machine_type" {
  description = "Machine type for all VMs"
  type        = string
  default     = "e2-medium" # 2 vCPU, 4GB
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "data_disk_size_gb" {
  description = "Data disk size in GB for Postgres"
  type        = number
  default     = 50
}

variable "mig_size" {
  description = "Target size of Spot MIG"
  type        = number
  default     = 2
}

variable "admin_ip_ranges" {
  description = "Allowed source CIDRs for SSH to on-demand VM"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cloudflare_ipv4_ranges" {
  description = "Cloudflare IPv4 ranges for proxy-to-origin access"
  type        = list(string)
  default     = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22"
  ]
}

variable "backup_bucket_name" {
  description = "GCS bucket for nightly backups"
  type        = string
  default     = "rn-backup-rural-neighbor-477211"
}

variable "enable_oslogin" {
  description = "Enable OS Login for SSH (recommended)"
  type        = bool
  default     = true
}


