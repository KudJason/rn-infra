terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }

  backend "gcs" {
    bucket = "tf-state-rural-neighbor-1"
    prefix = "terraform/vm-production"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
