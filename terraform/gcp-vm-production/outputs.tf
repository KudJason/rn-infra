# Production Terraform Outputs

output "prod_core_vm_name" {
  description = "Production Core VM name"
  value       = google_compute_instance.prod_core.name
}

output "prod_core_vm_ip" {
  description = "Production Core VM public IP address"
  value       = google_compute_address.prod_core_ip.address
}

output "prod_core_private_ip" {
  description = "Production Core VM private IP address"
  value       = google_compute_instance.prod_core.network_interface[0].network_ip
}

output "prod_worker_mig_name" {
  description = "Production Worker MIG name"
  value       = google_compute_region_instance_group_manager.prod_workers_v6.name
}

output "prod_worker_count" {
  description = "Target number of production worker VMs"
  value       = var.prod_mig_size
}

output "prod_backup_bucket" {
  description = "Production backup GCS bucket name"
  value       = google_storage_bucket.prod_backups.name
}

output "prod_vm_service_account" {
  description = "Production VM uses default Compute Service Account"
  value       = "default"
}
