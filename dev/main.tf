terraform {
  required_version = "= 1.17.2"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.8.1"
    }
  }
}

provider "google" {
  project = "aap-dev-e48b"
  region  = "europe-north1"
}

resource "google_storage_bucket" "terraform_state" {
  name                        = "aap-terraform-state-dev"
  location                    = "europe-north1"
  storage_class               = "STANDARD"
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}
