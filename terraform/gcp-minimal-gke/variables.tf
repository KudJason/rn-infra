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

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "rn-minimal-vpc"
}

variable "subnet_name" {
  description = "Subnetwork name"
  type        = string
  default     = "rn-minimal-subnet"
}

variable "subnet_ip_cidr" {
  description = "Primary CIDR for nodes (not used by Autopilot nodes, but required for control)"
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_secondary_range_name" {
  description = "Secondary range name for Pods"
  type        = string
  default     = "pods"
}

variable "pods_secondary_cidr" {
  description = "CIDR for Pods"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_secondary_range_name" {
  description = "Secondary range name for Services"
  type        = string
  default     = "services"
}

variable "services_secondary_cidr" {
  description = "CIDR for Services"
  type        = string
  default     = "10.30.0.0/20"
}

variable "cluster_name" {
  description = "GKE Autopilot cluster name"
  type        = string
  default     = "rn-autopilot-minimal"
}

variable "artifact_repo_id" {
  description = "Artifact Registry repository id"
  type        = string
  default     = "rn-backend"
}





