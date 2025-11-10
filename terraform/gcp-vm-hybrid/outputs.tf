output "core_vm_name" { value = google_compute_instance.core.name }
output "core_vm_ip" { value = google_compute_instance.core.network_interface[0].access_config[0].nat_ip }
output "backup_bucket" { value = google_storage_bucket.backup.name }
output "mig_name" { value = google_compute_instance_group_manager.spot_mig.name }





