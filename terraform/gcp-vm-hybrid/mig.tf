resource "google_compute_instance_template" "spot_tmpl" {
  name_prefix  = "rn-spot-tmpl-"
  machine_type = var.machine_type

  disk {
    source_image = data.google_compute_image.debian.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = "pd-standard"
  }

  network_interface {
    network = "default"
    access_config {}
  }

  tags = ["rn-mig"]

  metadata = {
    startup-script         = <<-EOT
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \n"\
  "$(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
echo "Spot worker ready"
EOT
    enable-oslogin         = var.enable_oslogin ? "TRUE" : "FALSE"
    block-project-ssh-keys = "TRUE"
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }

  scheduling {
    provisioning_model         = "SPOT"
    preemptible                = true
    instance_termination_action = "STOP"
    automatic_restart          = false
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

resource "google_compute_instance_group_manager" "spot_mig" {
  name               = "rn-spot-mig"
  base_instance_name = "rn-spot"
  zone               = var.zone
  target_size        = var.mig_size

  version {
    instance_template = google_compute_instance_template.spot_tmpl.self_link
  }
}





