# Dev cluster - hosts BOTH the dev and staging namespaces (see argocd module's
# `env` validation comment). Node group sized a little more generously than a
# pure single-namespace dev would need, to absorb both namespaces' workloads.

# vpc
name               = "devops-task-dev"
cidr               = "10.0.0.0/16"
azs                = ["us-east-1a", "us-east-1b"]
private_subnets    = ["10.0.0.0/20", "10.0.16.0/20"]
public_subnets     = ["10.0.128.0/20", "10.0.144.0/20"]
single_nat_gateway = true # cheap/non-HA, fine for dev

# shared identically across vpc/eks/alb-controller/external-secrets/monitoring
cluster_name = "devops-task-dev"
region       = "us-east-1"

# eks
enable_cluster_encryption = false # keep dev cheap/fast; prod turns this on
eks_managed_node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "SPOT"
    min_size       = 1
    desired_size   = 2
    max_size       = 4
  }
}

# external-secrets - one ClusterSecretStore on this cluster serves both the
# dev and staging namespaces, so both secret paths are allowed here.
secret_arns = [
  "arn:aws:secretsmanager:us-east-1:302954730632:secret:devops-task/dev/*",
  "arn:aws:secretsmanager:us-east-1:302954730632:secret:devops-task/staging/*",
]

# monitoring - smallest/shortest retention tier
retention               = "5d"
prometheus_storage_size = "10Gi"
grafana_storage_size    = "5Gi"

# argocd (github_oauth_client_id/secret are NOT set here - export
# TF_VAR_github_oauth_client_id / TF_VAR_github_oauth_client_secret before
# apply instead, so no OAuth credential ever touches this public repo)
gitops_repo_url       = "https://github.com/yoavmanoim-prog/devops-task-gitops.git"
admin_github_username = "yoavmanoim-prog"

tags = {
  Environment = "dev"
  Project     = "devops-task"
}
