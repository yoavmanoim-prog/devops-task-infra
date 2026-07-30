# Root Terragrunt config: S3 backend + AWS provider `generate` blocks only -
# no module wiring lives here. Named root.hcl (not terragrunt.hcl) so it can
# never be mistaken for a runnable unit itself; every real unit's
# terragrunt.hcl finds this via find_in_parent_folders("root.hcl").
#
# State bucket + lock table are account-level, pre-existing infra that this
# config assumes already exists (bootstrap is a one-time manual step, see
# infra/README.md) - Terragrunt/Terraform can't create the backend they're
# about to store their own state in.
locals {
  aws_region = "us-east-1"
  account_id = "302954730632"
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "devops-task-tfstate-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = "devops-task-tflocks"
    encrypt        = true
  }
}

generate "provider_aws" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Project   = "devops-task"
          ManagedBy = "terragrunt"
        }
      }
    }
  EOF
}
