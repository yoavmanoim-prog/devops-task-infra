variable "namespace" {
  type    = string
  default = "monitoring"
}

variable "chart_version" {
  description = "kube-prometheus-stack Helm chart version. Verify with: helm search repo prometheus-community/kube-prometheus-stack --versions"
  type        = string
  default     = "87.16.1"
}

variable "retention" {
  description = "How long Prometheus keeps metrics locally (Prometheus retention window, e.g. '3d', '15d')"
  type        = string
  default     = "10d"
}

variable "prometheus_storage_size" {
  description = "Size of the EBS-backed PVC Prometheus's StatefulSet mounts (via storageSpec.volumeClaimTemplate) - no in-cluster HA/cross-AZ replication of this volume in this demo, noted as a limitation."
  type        = string
  default     = "20Gi"
}

variable "prometheus_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "250m", memory = "512Mi" }
    limits   = { cpu = "500m", memory = "1Gi" }
  }
}

variable "grafana_storage_size" {
  type    = string
  default = "5Gi"
}

variable "grafana_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "200m", memory = "256Mi" }
  }
}

variable "enable_alert_delivery" {
  description = "Route fired alerts to an SNS topic instead of discarding them. kube-prometheus-stack's default Alertmanager config sends everything to a receiver named \"null\", so out of the box its ~100 bundled rules evaluate, fire and vanish - monitoring that cannot notify anyone. Off by default because it creates billable AWS resources and is pointless without a subscriber."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email subscribed to the alerts topic. AWS sends a confirmation link that must be clicked before anything is delivered - an unconfirmed subscription silently drops messages, which is the same failure this whole feature exists to remove. Leave empty to create the topic with no subscriber."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region, used for Alertmanager's SigV4 signing of SNS publishes."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name, used to name the SNS topic and IAM role and to label alerts by origin."
  type        = string
}

variable "oidc_provider_arn" {
  description = "The cluster's IAM OIDC provider ARN, from the eks module. Only needed when enable_alert_delivery is true - Alertmanager assumes its role through web-identity federation rather than holding a key."
  type        = string
  default     = ""
}

variable "oidc_provider" {
  description = "The cluster's OIDC issuer host (no scheme), from the eks module. Used to build the sub/aud condition keys in the trust policy."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the AWS resources this module creates (SNS topic, Alertmanager IAM role). The Kubernetes objects are unaffected."
  type        = map(string)
  default     = {}
}
