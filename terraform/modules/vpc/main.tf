# Thin wrapper around the community terraform-aws-modules/vpc/aws module.
#
# Why a wrapper instead of calling the registry module directly from
# Terragrunt: it lets us fix the module version and the EKS-specific subnet
# tagging conventions (kubernetes.io/role/elb, kubernetes.io/role/internal-elb,
# kubernetes.io/cluster/<name>=shared) in exactly one place, so every
# environment inherits the same, correct networking contract for both the
# in-tree AWS Load Balancer subnet auto-discovery and the EKS control plane.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1" # verified latest as of 2026-07-30 - https://github.com/terraform-aws-modules/terraform-aws-vpc/releases

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Required so pods (private subnets) can reach the internet (image pulls,
  # AWS APIs) and so EKS control plane <-> node communication resolves.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC flow logs give us a baseline of network observability / auditability
  # for a "production-grade configuration approach" without needing a SIEM.
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 30

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = var.tags
}
