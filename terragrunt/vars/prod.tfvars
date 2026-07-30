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
eks_managed_node_groups = {
  general = {
    instance_types = ["m6i.large"]
    capacity_type  = "ON_DEMAND"
    min_size       = 2
    desired_size   = 3
    max_size       = 6
  }
  system = {
    instance_types = ["m6i.large"]
    capacity_type  = "ON_DEMAND"
    min_size       = 1
    desired_size   = 1
    max_size       = 2
    taints = [{
      key    = "dedicated"
      value  = "system"
      effect = "NO_SCHEDULE"
    }]
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
