variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster's OIDC provider ARN (module.eks.oidc_provider_arn) - required for IRSA trust policy. The issuer URL itself isn't needed as a separate input: the iam-role-for-service-accounts submodule derives it from this ARN."
  type        = string
}

variable "namespace" {
  description = "Namespace the External Secrets Operator control plane runs in (cluster-scoped operator, separate from the app namespaces it syncs secrets into)"
  type        = string
  default     = "external-secrets"
}

variable "chart_version" {
  description = "external-secrets Helm chart version. Verify with: helm search repo external-secrets/external-secrets --versions"
  type        = string
  default     = "0.20.2"
}

variable "secret_arns" {
  description = "Secrets Manager / SSM ARNs (or ARN prefixes with a trailing *) this cluster's ExternalSecrets are allowed to read. Kept narrow per-environment so a compromised dev pod can't read prod secrets."
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
