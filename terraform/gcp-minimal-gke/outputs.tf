output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "network" {
  value = google_compute_network.vpc.name
}

output "subnet" {
  value = google_compute_subnetwork.subnet.name
}

output "artifact_registry_repo" {
  value = google_artifact_registry_repository.docker.repository_id
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gke_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "storage_bucket_name" {
  description = "GCS bucket name for file storage"
  value       = google_storage_bucket.files.name
}

output "storage_bucket_url" {
  description = "GCS bucket base URL"
  value       = "https://storage.googleapis.com/${google_storage_bucket.files.name}"
}





