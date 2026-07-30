variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "region" {
  type = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster's OIDC provider ARN (module.eks.oidc_provider_arn) - required for IRSA trust policy"
  type        = string
}

variable "oidc_provider" {
  description = "EKS cluster's OIDC provider issuer, without the https:// prefix (module.eks.oidc_provider)"
  type        = string
}

variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version. Chart versioning was realigned to match the controller's own app version starting with chart v3.0.0."
  type        = string
  default     = "1.13.4" # verify with: helm search repo eks/aws-load-balancer-controller --versions
}

variable "namespace" {
  type    = string
  default = "kube-system"
}

variable "tags" {
  type    = map(string)
  default = {}
}
