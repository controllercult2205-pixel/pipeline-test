# Test root 2: a bucket created through a local module.
# Module test: change modules/simple-bucket and only this root is planned.
module "test_bucket" {
  source = "../../../modules/simple-bucket"

  name     = "ipam-conn-pn20482-pipeline-test"
  location = "asia-south1"
}
