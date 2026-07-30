variable "cluster_name" {
  type = string
}

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

variable "tags" {
  type    = map(string)
  default = {}
}
