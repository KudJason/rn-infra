resource "google_project_service" "enabled" {
  for_each = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
  ])
  project = var.project_id
  service = each.value
}





