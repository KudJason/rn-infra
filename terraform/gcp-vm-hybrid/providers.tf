terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }

  backend "gcs" {
    # NOTE: keep this in sync with PROJECT_ID when using setup-gcloud-for-terraform.sh
    bucket = "tf-state-rural-neighbor-1"
    prefix = "terraform/vm-hybrid"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}




