resource "google_kms_key_ring" "rn" {
  name     = "rn-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "app" {
  name            = "app-config"
  key_ring        = google_kms_key_ring.rn.id
  rotation_period = "2592000s" # 30 days
  purpose         = "ENCRYPT_DECRYPT"
}

# 允许 VM SA 使用此密钥加解密（用于 Secret Manager 的客户管理密钥）
resource "google_kms_crypto_key_iam_member" "app_sa_use" {
  crypto_key_id = google_kms_crypto_key.app.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.vm_sa.email}"
}



