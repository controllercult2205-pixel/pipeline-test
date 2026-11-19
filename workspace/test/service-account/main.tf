# Test root 1: a harmless service account (no roles).
# Drift test: change its description in the console, then run the drift check.
resource "google_service_account" "pipeline_test" {
  account_id   = "pipeline-test-sa"
  display_name = "Pipeline test SA"
  description  = "Created by the Terraform pipeline test"
}
