resource "google_service_account" "vm_sa" {
  account_id   = "rn-vm-sa"
  display_name = "RuralNeighbour VM Service Account"
}

# 最小需要：写日志/监控 + 备份桶写权限
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
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

resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm_sa.email}"
}





