output "vm_name" {
  value = google_compute_instance.vm.name
}

output "vm_external_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/<your_key> <user>@${google_compute_instance.vm.network_interface[0].access_config[0].nat_ip}"
}





