include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.env
}

terraform {
  source = "${get_repo_root()}/terraform/modules//argocd"

  extra_arguments "env_vars" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_repo_root()}/terragrunt/vars/${local.env}.tfvars",
    ]
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "devops-task-mock"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

generate "provider_k8s_helm" {
  path      = "provider_k8s_helm.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.35"
        }
      }
    }

    data "aws_eks_cluster_auth" "this" {
      name = "${dependency.eks.outputs.cluster_name}"
    }

    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
      token                  = data.aws_eks_cluster_auth.this.token
    }

    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        token                  = data.aws_eks_cluster_auth.this.token
      }
    }
  EOF
}

# github_oauth_client_id / github_oauth_client_secret are deliberately NOT
# set here or in vars/prod.tfvars - export TF_VAR_github_oauth_client_id and
# TF_VAR_github_oauth_client_secret in the shell before apply instead, so no
# OAuth credential ever gets committed to this public repo.
inputs = {
  env = local.env
}
