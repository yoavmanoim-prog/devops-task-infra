# Thin wrapper around terraform-aws-modules/eks/aws.
#
# NOTE ON VERSION VERIFICATION: this module's input schema changes between
# major versions (v19 -> v20 -> v21 reworked node group and access-entry
# inputs significantly). The attributes below match the v21 line as
# documented at https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.24.0
# at the time this was written (2026-07-30). Before `terragrunt apply`,
# re-run `terraform providers schema` / check the pinned registry page,
# since these community modules ship breaking changes on minor bumps too.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0" # verified latest as of 2026-07-30 - https://github.com/terraform-aws-modules/terraform-aws-eks/releases

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enabled_log_types = var.cluster_log_types

  # EKS Access Entry API replaces the aws-auth ConfigMap as the
  # recommended way to manage cluster access; API_AND_CONFIG_MAP keeps
  # both paths open during any migration off aws-auth.
  authentication_mode                      = var.authentication_mode
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    for idx, role_arn in var.admin_role_arns :
    "admin-${idx}" => {
      principal_arn = role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  create_kms_key = var.enable_cluster_encryption
  cluster_encryption_config = var.enable_cluster_encryption ? {
    resources = ["secrets"]
  } : {}

  enable_irsa = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = var.eks_managed_node_groups

  # The AWS Load Balancer Controller's admission webhook runs on nodes and
  # must be reachable from the control plane on 9443, or ALB/Ingress
  # reconciliation silently fails with webhook timeout errors.
  node_security_group_additional_rules = {
    ingress_alb_controller_webhook = {
      description                   = "Cluster API to node webhooks (aws-load-balancer-controller, etc.)"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = var.tags
}
