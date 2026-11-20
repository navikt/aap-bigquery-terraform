terraform {
  backend "gcs" {
    bucket = "aap-terraform-state-dev"
  }
}