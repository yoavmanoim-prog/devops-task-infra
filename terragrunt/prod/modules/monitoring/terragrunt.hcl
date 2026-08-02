include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.env
}

terraform {
  source = "${get_repo_root()}/terraform/modules//monitoring"

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
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

generate "provider_k8s_helm" {
  path      = "provider_k8s_helm.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
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

# Alertmanager assumes an IAM role via web identity to publish to SNS, so it
# needs the cluster's OIDC provider. Only used when enable_alert_delivery.
inputs = {
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider     = dependency.eks.outputs.oidc_provider
}
