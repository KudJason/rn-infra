resource "google_service_account" "vm_sa" {
  account_id   = "rn-vm-sa"
  display_name = "RuralNeighbour VM Service Account"
}

resource "google_storage_bucket" "backup" {
  name                        = var.backup_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false
  versioning { enabled = true }
  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 30 }
  }
}

# Grant Secret Manager access to VM service account
resource "google_secret_manager_secret_iam_member" "vm_sa_db_password" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "vm_sa_jwt_secret" {
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "vm_sa_k3s_token" {
  secret_id = google_secret_manager_secret.k3s_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "vm_sa_ghcr_credentials" {
  secret_id = google_secret_manager_secret.ghcr_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

# IAM bindings for other services (logging, monitoring, storage) removed - will be managed manually or via gcloud if needed
# To grant permissions manually, use:
#   gcloud projects add-iam-policy-binding PROJECT_ID --member="serviceAccount:rn-vm-sa@PROJECT_ID.iam.gserviceaccount.com" --role="roles/logging.logWriter"
#   gcloud projects add-iam-policy-binding PROJECT_ID --member="serviceAccount:rn-vm-sa@PROJECT_ID.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
#   gsutil iam ch serviceAccount:rn-vm-sa@PROJECT_ID.iam.gserviceaccount.com:roles/storage.objectAdmin gs://BUCKET_NAME





