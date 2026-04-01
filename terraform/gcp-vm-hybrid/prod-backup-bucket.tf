resource "google_storage_bucket" "prod_backups" {
  name     = var.prod_backup_bucket_name
  location = "US"

  storage_class = "STANDARD"

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
