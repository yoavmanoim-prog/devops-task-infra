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

# IRSA role for the EBS CSI driver addon above. Same pattern as the
# alb-controller / external-secrets modules: a workload-scoped IAM identity
# rather than granting EC2 volume permissions to the whole node role.
#
# Depends on the cluster's OIDC provider, which module.eks creates - Terraform
# resolves that ordering from the module.eks.oidc_provider_arn reference.
module "irsa_ebs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name                  = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
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
      # NetworkPolicy enforcement. The node agent ships in this addon but runs
      # with --enable-network-policy=false, so without this the gitops repo's
      # default-deny policies are accepted by the API and enforced by nothing:
      # `kubectl get networkpolicy` shows them, and staging can still reach
      # dev. A silent no-op is worse than a missing control, because it reads
      # as configured. See var.enable_network_policy for the ALB caveat.
      configuration_values = jsonencode({
        enableNetworkPolicy = var.enable_network_policy ? "true" : "false"
      })
    }
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
    }
    # Not optional on modern EKS. The cluster's built-in `gp2` StorageClass
    # uses the in-tree kubernetes.io/aws-ebs provisioner, which Kubernetes
    # REMOVED in 1.31 - on 1.34 it can never bind a volume, so every PVC sits
    # Pending ("no persistent volumes available for this claim") and any chart
    # waiting on one times out. Needs its own IRSA role because the driver
    # calls the EC2 API to create and attach volumes.
    #
    # Caveat documented in infra/README.md: EBS volumes are AZ-scoped, so a
    # SPOT reclaim can strand a pod whose volume lives in an AZ that no longer
    # has a node. Thanos->S3 (metrics) and RDS (Grafana's DB) are the real
    # fixes; both are described there.
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.irsa_ebs_csi.arn
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
