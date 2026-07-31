variable "env" {
  description = "Which cluster this ArgoCD instance runs on - controls which path in the gitops repo its bootstrap Application watches. Only 2 clusters exist (dev, prod); the dev cluster hosts both the dev and staging namespaces, so this instance's bootstrap Application (apps/dev) fans out to both via an ApplicationSet defined in the gitops repo - it is not a 1:1 cluster:namespace mapping for dev."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be one of: dev, prod (staging is a namespace on the dev cluster, not a separate ArgoCD instance)."
  }
}

variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  description = "argo-cd Helm chart version (chart 10.2.1 ships ArgoCD app v3.4.5). Verify with: helm search repo argo/argo-cd --versions"
  type        = string
  default     = "10.2.1"
}

variable "gitops_repo_url" {
  description = "HTTPS clone URL of the gitops repo this ArgoCD instance reconciles against"
  type        = string
}

variable "admin_github_username" {
  description = "GitHub username (as returned by the Dex github connector) mapped to ArgoCD's built-in role:admin. Everyone else who authenticates via GitHub OAuth falls back to role:readonly (ArgoCD's policy.default)."
  type        = string
}

variable "github_oauth_client_id" {
  description = "Client ID of the GitHub OAuth App backing ArgoCD SSO. Not secret, but sourced as a variable rather than hardcoded so the same module works before the OAuth App exists (placeholder) and after."
  type        = string
}

variable "github_oauth_client_secret" {
  description = "Client secret of the GitHub OAuth App backing ArgoCD SSO. Stored only in a Kubernetes Secret (labelled app.kubernetes.io/part-of=argocd so Dex can resolve it via the $<secret>:<key> syntax), never inlined into Helm values or ArgoCD ConfigMaps."
  type        = string
  sensitive   = true
}

variable "argocd_external_url" {
  description = "Public URL ArgoCD will be reachable at (used for the Dex OAuth redirect URI and configs.cm.url). Typically the NLB hostname; update once the LoadBalancer Service has been provisioned and re-apply."
  type        = string
  default     = ""
}
