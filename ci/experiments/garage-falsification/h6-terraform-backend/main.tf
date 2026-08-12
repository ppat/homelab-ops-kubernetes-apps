terraform {
  # 1.6.6 pinned deliberately -- the last MPL-licensed release, and the version pinned
  # elsewhere in this estate. This is what has to move off MinIO before it can be
  # decommissioned, so it's the exact binary under test, not "a recent Terraform".
  required_version = "= 1.6.6"

  required_providers {
    local  = { source = "hashicorp/local", version = "~> 2.4" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "s3" {
    bucket = "h6falsify"
    key    = "throwaway/terraform.tfstate"
    region = "garage"

    # Garage-against-a-generic-S3-backend flags: no real AWS account, path-style addressing
    # (Garage has no wildcard DNS for virtual-hosted-style buckets in this setup), and skip
    # every AWS-specific API call the S3 backend would otherwise make that Garage doesn't
    # implement (region validation, credentials chain, EC2 metadata).
    endpoints = {
      s3 = "http://127.0.0.1:16900"
    }
    force_path_style             = true  # named explicitly in the H6 brief; this terraform/backend version warns
    # it's deprecated in favor of use_path_style but still functions -- kept as specified rather than silently swapped.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    # access_key/secret_key deliberately NOT here -- passed at `terraform init` time via
    # -backend-config so no credential (even a throwaway sandbox one) is ever committed.
  }
}

# Throwaway dummy resources only -- this workspace never touches any real state, per the H6
# brief ("do not touch any real state").
resource "local_file" "dummy_a" {
  filename = "${path.module}/.dummy_a.txt"
  content  = "h6-falsification-dummy-a"
}

resource "local_file" "dummy_b" {
  filename = "${path.module}/.dummy_b.txt"
  content  = "h6-falsification-dummy-b"
}

resource "random_id" "dummy" {
  byte_length = 8
}
