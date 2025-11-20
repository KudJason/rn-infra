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

variable "instance_name" {
  description = "VM name"
  type        = string
  default     = "rn-backend-vm"
}

variable "machine_type" {
  description = "Compute Engine machine type"
  type        = string
  default     = "e2-medium" # 2 vCPU, 4GB
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "allow_source_ranges" {
  description = "Firewall allowed source CIDRs"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}





