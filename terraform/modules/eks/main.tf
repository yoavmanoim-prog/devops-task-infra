# Thin wrapper around terraform-aws-modules/eks/aws.
#
# NOTE ON VERSION VERIFICATION: this module's input schema changes between
# major versions (v19 -> v20 -> v21 reworked node group and access-entry
# inputs significantly) - confirmed the hard way: `cluster_encryption_config`,
# `cluster_addons`, and `eks_managed_node_group_defaults` (all used in an
# earlier draft of this file, based on the v19/v20-era docs) are rejected
# outright by the actual v21.24.0 schema, verified directly against
# github.com/terraform-aws-modules/terraform-aws-eks's variables.tf at the
# refs/tags/v21.24.0 ref. Corrected below to `encryption_config`, `addons`,
# and a per-node-group `ami_type` default applied via a local (v21 has no
# separate node-group-defaults variable at all). Before `terragrunt apply`,
# re-check that same tagged ref's variables.tf, since these community
# modules ship breaking changes on minor bumps too.
locals {
  # v21's eks_managed_node_groups.taints is a map (keyed by an arbitrary
  # identifier, we use the taint's own key) of the *same* {key,value,effect}
  # object - not a bare list like the v19/v20 schema. Converted here so the
  # module's own public variable (var.eks_managed_node_groups, still a list
  # of taints for caller simplicity) doesn't need to change shape for every
  # tfvars file that sets one.
  eks_managed_node_groups = {
    for name, ng in var.eks_managed_node_groups :
    name => merge(
      { ami_type = "AL2023_x86_64_STANDARD" },
      ng,
      { taints = { for t in ng.taints : t.key => t } }
    )
  }
}

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
  encryption_config = var.enable_cluster_encryption ? {
    resources = ["secrets"]
  } : null

  enable_irsa = true

  # before_compute matters here and defaults to FALSE, which is wrong for the
  # networking addons: a node can't reach Ready without the VPC CNI (no pod
  # IPs) or kube-proxy, so with the default ordering Terraform builds the node
  # group first, every node fails its health check, and the whole node group
  # times out as CREATE_FAILED - which is exactly what happened on the first
  # attempt (cluster ACTIVE, `aws eks list-addons` empty, nodes never joined).
  #
  # coredns is deliberately left at before_compute = false: it's an ordinary
  # Deployment that needs schedulable nodes to run on, so installing it before
  # compute exists just leaves it Pending.
  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
    }
  }

  eks_managed_node_groups = local.eks_managed_node_groups

  # NOTE: no node_security_group_additional_rules here. An earlier version of
  # this module added an explicit control-plane -> node TCP/9443 ingress rule
  # for the AWS Load Balancer Controller's admission webhook. That is already
  # covered by v21's node_security_group_enable_recommended_rules (default
  # true), which creates ingress_cluster_{443,4443,6443,8443,9443}_webhook
  # plus kubelet and coredns rules. Declaring 9443 again failed the apply
  # outright with InvalidPermission.Duplicate, since both rules resolve to the
  # same (protocol, port, source SG) tuple. Re-check the module's recommended
  # set before adding any rule here - it is broader than it looks.

  tags = var.tags
}
