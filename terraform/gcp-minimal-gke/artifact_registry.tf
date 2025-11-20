resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.artifact_repo_id
  description   = "RuralNeighbour backend Docker repo"
  format        = "DOCKER"
  project       = var.project_id

  depends_on = [google_project_service.enabled]
}





