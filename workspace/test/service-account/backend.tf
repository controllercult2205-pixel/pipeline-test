terraform {
  backend "gcs" {
    bucket = "ipam-conn-pn20482-tfstate"
    prefix = "test/service-account"
  }
}
