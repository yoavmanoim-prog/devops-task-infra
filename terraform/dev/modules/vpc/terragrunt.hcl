include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.env
}

terraform {
  source = "${get_repo_root()}/terraform/modules//vpc"

  extra_arguments "env_vars" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_repo_root()}/terraform/vars/${local.env}.tfvars",
    ]
  }
}
