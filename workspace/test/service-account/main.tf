# Test root 1: a harmless service account (no roles).
# Drift test: change its description in the console, then run the drift check.
resource "google_service_account" "pipeline_test" {
  account_id   = "pipeline-test-sa"
  display_name = "Pipeline test SA"
  description  = "Created by the Terraform pipeline test"
}

resource "google_service_account" "second" {
  account_id   = "pipeline-test-sa-2"
  display_name = "Pipeline test SA 2"
}

resource "google_storage_bucket" "second" {
  name                        = "ipam-conn-pn20482-pipeline-test-2"
  location                    = "asia-south1"
  uniform_bucket_level_access = true
  force_destroy               = true
}
