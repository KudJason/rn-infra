# Service Account for Production VMs

resource "google_service_account" "vm_sa" {
  project      = var.project_id
  account_id   = "rn-prod-vm-sa"
  display_name = "RuralNeighbour Production VM Service Account"
}

resource "google_project_iam_member" "vm_sa_roles" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "vm_sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "vm_sa_secret_reader" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}
