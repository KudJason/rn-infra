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

# IAM bindings removed - will be managed manually or via gcloud if needed
# To grant KMS key access manually, use:
#   gcloud kms keys add-iam-policy-binding app-config --keyring=rn-keyring --location=REGION --member="serviceAccount:rn-vm-sa@PROJECT_ID.iam.gserviceaccount.com" --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"



