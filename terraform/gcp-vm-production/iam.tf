# IAM and GCS resources for production environment
# Follows the same pattern as staging (gcp-vm-staging/iam.tf) and dev (gcp-vm-hybrid/iam.tf)
# Manages a dedicated service account and GCS bucket for production file storage

# Production VM Service Account — separate from dev/staging for environment isolation
resource "google_service_account" "prod_vm_sa" {
  account_id   = "rn-prod-vm-sa"
  display_name = "RuralNeighbour Production VM Service Account"
}

# GCS bucket for production file storage (profile photos, etc.)
resource "google_storage_bucket" "prod_files" {
  name                        = var.prod_files_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 90 }
  }

  lifecycle_rule {
    action { type = "AbortIncompleteMultipartUpload" }
    condition { age = 1 }
  }
}

# Grant public read access for serving static content (profile photos, etc.)
resource "google_storage_bucket_iam_member" "prod_files_public_reader" {
  bucket = google_storage_bucket.prod_files.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Grant prod VM SA full access to the files bucket
resource "google_storage_bucket_iam_member" "prod_files_vm_sa_admin" {
  bucket = google_storage_bucket.prod_files.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.prod_vm_sa.email}"
}

# Grant prod VM SA write access to the nightly backup bucket (pg_dumpall via gsutil)
resource "google_storage_bucket_iam_member" "prod_backups_vm_sa_admin" {
  bucket = google_storage_bucket.prod_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.prod_vm_sa.email}"
}
