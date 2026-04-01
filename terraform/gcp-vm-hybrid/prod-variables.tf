variable "prod_on_demand_name" {
  description = "Production On-demand VM name"
  type        = string
  default     = "rn-prod-core-vm"
}

variable "prod_machine_type" {
  description = "Machine type for production VM"
  type        = string
  default     = "e2-standard-2" # 2 vCPU, 8GB
}

variable "prod_boot_disk_size_gb" {
  description = "Boot disk size in GB for production VM"
  type        = number
  default     = 100
}

variable "prod_data_disk_size_gb" {
  description = "Data disk size in GB for production"
  type        = number
  default     = 100
}

variable "prod_worker_machine_type" {
  description = "Machine type for production worker VMs"
  type        = string
  default     = "e2-small" # 2 vCPU, 2GB
}

variable "prod_worker_disk_size_gb" {
  description = "Boot disk size in GB for production worker VMs"
  type        = number
  default     = 20
}

variable "prod_mig_size" {
  description = "Target size of production worker MIG"
  type        = number
  default     = 2
}

variable "prod_backup_bucket_name" {
  description = "GCS bucket for production nightly backups"
  type        = string
  default     = "rn-prod-backups-rural-neighbor-1"
}

variable "prod_target_node_count" {
  description = "Target K8s node count (1 master + workers)"
  type        = number
  default     = 3 # 1 master + 2 workers
}
