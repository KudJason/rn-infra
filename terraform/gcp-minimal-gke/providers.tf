terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }

  backend "gcs" {
    bucket = "tf-state-rural-neighbor-477211"
    prefix = "terraform/gke-minimal"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}


