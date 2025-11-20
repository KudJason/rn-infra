resource "google_container_cluster" "primary" {
  name                = var.cluster_name
  location            = var.region
  enable_autopilot    = true
  network             = google_compute_network.vpc.self_link
  subnetwork          = google_compute_subnetwork.subnet.self_link
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.enabled, google_compute_subnetwork.subnet]
}





