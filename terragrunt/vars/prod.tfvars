# Prod cluster - hosts only the production namespace, tighter security/sizing.

# vpc
name               = "devops-task-prod"
cidr               = "10.1.0.0/16"
azs                = ["us-east-1a", "us-east-1b"] # private/public subnet CIDRs are derived from cidr+azs in the vpc module, not listed here
single_nat_gateway = false                        # one NAT per AZ - no single point of failure

# shared identically across vpc/eks/alb-controller/external-secrets/monitoring
cluster_name = "devops-task-prod"
region       = "us-east-1"

# eks
enable_cluster_encryption = true # envelope-encrypt secrets at rest in prod
# One node group, not two. The second ("system", tainted NO_SCHEDULE) had
# nothing tolerating it anywhere in the gitops repo, so it would have run
# permanently empty at full cost - it was reserved for future workloads that
# don't exist.
#
# THREE nodes, not two, and the binding constraint is pod COUNT, not CPU.
# A t3.medium allows only 17 pods under the VPC CNI's default per-ENI IP
# allocation, while CPU allocatable is 1930m/node and the whole stack only
# requests ~2.4 vCPU. At 2 nodes prod filled one node to 17/17, which left a
# node-exporter DaemonSet pod permanently Pending (it can only run on the
# full node, since the other already has one) and left just 6 free slots for
# app-production, whose HPA can scale to 8.
#
# The zero-cost alternative is VPC CNI prefix delegation
# (ENABLE_PREFIX_DELEGATION, 17 -> 110 pods/node), but it only takes effect
# on newly-allocated ENIs, so it needs both node groups cycled - restarting
# every running pod. A third SPOT node is ~$0.30/day and needs no disruption.
# See infra/README.md for the trade-off.
#
# Only desired_size changes: that is what actually sets the node count. There
# is no cluster-autoscaler here, so nothing ever scales this group and
# min_size/max_size are just bounds that never bind. (Raising min_size to 3
# alongside desired was also rejected outright by EKS - it validates
# min <= desired against CURRENT state, so min=3 failed while desired was
# still 2. If a SPOT node is reclaimed the ASG replaces it to return to
# desired_size regardless of min_size.)
eks_managed_node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "SPOT"
    min_size       = 2
    desired_size   = 3
    max_size       = 4
  }
}

# external-secrets
secret_arns = [
  "arn:aws:secretsmanager:us-east-1:302954730632:secret:devops-task/production/*",
]

# monitoring - largest/longest retention tier
retention               = "15d"
prometheus_storage_size = "50Gi"
grafana_storage_size    = "10Gi"

# argocd (github_oauth_client_id/secret via TF_VAR_ env vars, not here)
gitops_repo_url       = "https://github.com/yoavmanoim-prog/devops-task-gitops.git"
admin_github_username = "yoavmanoim-prog"

tags = {
  Environment = "prod"
  Project     = "devops-task"
}
