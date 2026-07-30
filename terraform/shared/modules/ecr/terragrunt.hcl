include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules//ecr"

  extra_arguments "shared_vars" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_repo_root()}/terraform/vars/shared.tfvars",
    ]
  }
}
