variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "rural-neighbor-1"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-c"
}

# Production Core VM
variable "prod_on_demand_name" {
  description = "Production On-demand VM name"
  type        = string
  default     = "rn-prod-core-vm"
}

variable "prod_machine_type" {
  description = "Machine type for production Core VM"
  type        = string
  default     = "e2-standard-2"
}

variable "prod_boot_disk_size_gb" {
  description = "Boot disk size in GB for production Core VM"
  type        = number
  default     = 100
}

variable "prod_data_disk_size_gb" {
  description = "Data disk size in GB for production"
  type        = number
  default     = 100
}

# Production Worker VMs
variable "prod_worker_machine_type" {
  description = "Machine type for production worker VMs"
  type        = string
  default     = "e2-small"
}

variable "prod_worker_disk_size_gb" {
  description = "Boot disk size in GB for production worker VMs"
  type        = number
  default     = 20
}

variable "prod_mig_size" {
  description = "Fixed worker MIG size (autoscaling OFF — see worker-mig.tf note)"
  type        = number
  default     = 2
}

variable "prod_target_node_count" {
  description = "Target K8s node count (1 master + workers)"
  type        = number
  default     = 3
}

# Network
variable "admin_ip_ranges" {
  description = "Allowed source CIDRs for SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cloudflare_ipv4_ranges" {
  description = "Cloudflare IPv4 ranges for proxy-to-origin access"
  type        = list(string)
  default = [
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

# Backup
variable "prod_backup_bucket_name" {
  description = "GCS bucket for production nightly backups"
  type        = string
  default     = "rn-prod-backups-rural-neighbor-1"
}

# Files storage
variable "prod_files_bucket_name" {
  description = "GCS bucket for production file storage (profile photos, etc.)"
  type        = string
  default     = "ruralneighbor-prod-files"
}

# Ingress
variable "ingress_controller" {
  description = "Ingress Controller: 'traefik' or 'nginx'"
  type        = string
  default     = "traefik"
}

variable "ingress_nodeport_http" {
  description = "NodePort for HTTP (nginx only)"
  type        = number
  default     = 30080
}

variable "ingress_nodeport_https" {
  description = "NodePort for HTTPS (nginx only)"
  type        = number
  default     = 30443
}
