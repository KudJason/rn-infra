resource "google_secret_manager_secret" "db_password" {
  secret_id  = "db-password"
  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.app.id
        }
      }
    }
  }
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id  = "jwt-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.app.id
        }
      }
    }
  }
}

# 允许核心 VM 的 SA 读取密钥
resource "google_secret_manager_secret_iam_member" "db_accessor" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "jwt_accessor" {
  secret_id = google_secret_manager_secret.jwt_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret" "k3s_token" {
  secret_id = "K3S_CLUSTER_TOKEN"
  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.app.id
        }
      }
    }
  }
}

# 允许 VM SA 更新 K3S Token 版本
resource "google_secret_manager_secret_iam_member" "k3s_token_writer" {
  secret_id = google_secret_manager_secret.k3s_token.id
  role      = "roles/secretmanager.secretVersionManager"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

# 注意：密钥值不写入代码库。请使用以下命令添加版本：
#   echo -n "<your_db_password>" | gcloud secrets versions add db-password --data-file=- --project ${var.project_id}
#   echo -n "<your_jwt_secret>"   | gcloud secrets versions add jwt-secret   --data-file=- --project ${var.project_id}



