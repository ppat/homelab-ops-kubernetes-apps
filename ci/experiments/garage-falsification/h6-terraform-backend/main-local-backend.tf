terraform {
  required_version = "= 1.6.6"

  required_providers {
    local  = { source = "hashicorp/local", version = "~> 2.4" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Step 1 baseline only: a local backend to establish known-good state and a "no changes"
  # plan to compare the Garage-migrated state against. Never used for anything but this
  # baseline -- ../README.md and run.sh explain the full sequence.
  backend "local" {}
}

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
