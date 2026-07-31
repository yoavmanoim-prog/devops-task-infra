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
# don't exist. min_size is 2 rather than 1 on purpose: the whole prod stack
# (app + ArgoCD + kube-prometheus-stack + controllers) needs ~2.4 vCPU of
# requests, so a SPOT reclaim down to a single 2-vCPU node would leave pods
# Pending. 2 nodes = ~65% CPU / ~48% memory committed, which has headroom.
eks_managed_node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "SPOT"
    min_size       = 2
    desired_size   = 2
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
