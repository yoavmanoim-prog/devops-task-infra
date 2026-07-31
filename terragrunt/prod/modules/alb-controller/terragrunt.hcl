include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.env
}

terraform {
  source = "${get_repo_root()}/terraform/modules//alb-controller"

  extra_arguments "env_vars" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_repo_root()}/terragrunt/vars/${local.env}.tfvars",
    ]
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "devops-task-mock"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    oidc_provider_arn                  = "arn:aws:iam::302954730632:oidc-provider/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# eks's own module only requires the aws provider (addons go through the AWS
# API, not a k8s client) - modules that install workloads onto the cluster
# (this one, external-secrets, argocd, monitoring) need their own kubernetes
# and/or helm provider, authenticated via the aws_eks_cluster_auth data
# source against this specific cluster's endpoint - so each such module gets
# this same generate block, parameterized by its own `dependency "eks"`.
generate "provider_k8s_helm" {
  path      = "provider_k8s_helm.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_eks_cluster_auth" "this" {
      name = "${dependency.eks.outputs.cluster_name}"
    }

    # No kubernetes provider here on purpose: this module only creates an IRSA
    # role and a helm_release, so configuring a provider it never uses would
    # misrepresent its dependencies. helm still needs the cluster auth token
    # below, which is why the aws_eks_cluster_auth data source stays.
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        token                  = data.aws_eks_cluster_auth.this.token
      }
    }
  EOF
}

inputs = {
  vpc_id            = dependency.vpc.outputs.vpc_id
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
}
