resource "google_secret_manager_secret" "db_password" {
  secret_id = "db-password"

  # 始终使用 user_managed 复制；仅在 manage_project_iam=true 时附加 CMEK
  replication {
    user_managed {
      replicas {
        location = var.region

        dynamic "customer_managed_encryption" {
          for_each = var.manage_project_iam ? [1] : []
          content {
            kms_key_name = google_kms_crypto_key.app.id
          }
        }
      }
    }
  }
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "jwt-secret"

  replication {
    user_managed {
      replicas {
        location = var.region

        dynamic "customer_managed_encryption" {
          for_each = var.manage_project_iam ? [1] : []
          content {
            kms_key_name = google_kms_crypto_key.app.id
          }
        }
      }
    }
  }
}

# IAM bindings removed - will be managed manually or via gcloud if needed

resource "google_secret_manager_secret" "k3s_token" {
  secret_id = "K3S_CLUSTER_TOKEN"

  replication {
    user_managed {
      replicas {
        location = var.region

        dynamic "customer_managed_encryption" {
          for_each = var.manage_project_iam ? [1] : []
          content {
            kms_key_name = google_kms_crypto_key.app.id
          }
        }
      }
    }
  }
}

# IAM bindings for Secret Manager access are managed in iam.tf

# 注意：密钥值不写入代码库。请使用以下命令添加版本：
#   echo -n "<your_db_password>" | gcloud secrets versions add db-password --data-file=- --project ${var.project_id}
#   echo -n "<your_jwt_secret>"   | gcloud secrets versions add jwt-secret   --data-file=- --project ${var.project_id}



