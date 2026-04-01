output "prod_core_vm_name" {
  description = "Production Core VM name"
  value      = google_compute_instance.prod_core.name
}

output "prod_core_vm_ip" {
  description = "Production Core VM public IP address"
  value      = google_compute_instance.prod_core.network_interface[0].access_config[0].nat_ip
}

output "prod_core_vm_private_ip" {
  description = "Production Core VM private IP address"
  value      = google_compute_instance.prod_core.network_interface[0].network_ip
}

output "prod_worker_mig_name" {
  description = "Production Worker MIG name"
  value      = google_compute_instance_group_manager.prod_worker_mig.name
}

output "prod_worker_instance_count" {
  description = "Number of production worker instances"
  value      = google_compute_instance_group_manager.prod_worker_mig.target_size
}

output "prod_backup_bucket" {
  description = "Production backup GCS bucket name"
  value      = var.prod_backup_bucket_name
}
