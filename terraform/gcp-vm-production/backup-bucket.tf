# Production Backup GCS Bucket

resource "google_storage_bucket" "prod_backups" {
  name     = var.prod_backup_bucket_name
  location = "US"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30
    }
  }

  versioning {
    enabled = true
  }

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
