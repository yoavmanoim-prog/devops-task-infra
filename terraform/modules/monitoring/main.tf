# kube-prometheus-stack bundles Prometheus, Alertmanager, Grafana and the
# standard scrape config/rules (kube-state-metrics, node-exporter, operator
# CRDs). Treated as core cluster infra (same tier as the ALB controller and
# External Secrets Operator) rather than an ArgoCD-managed app, so it's
# provisioned by Terraform before any workload can rely on it for
# dashboards/alerts.
#
# The Grafana admin password is generated here (never hardcoded, never
# passed through Helm `values` in plaintext) and handed to the chart via
# `existingSecret`, so it never appears in Helm release history or state
# in cleartext form outside this one Kubernetes Secret.

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "grafana_admin" {
  length           = 20
  special          = true
  override_special = "!#%&*-_=+"
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin-credentials"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }

  type = "Opaque"
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = var.retention
          resources = var.prometheus_resources
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = var.prometheus_storage_size }
                }
              }
            }
          }
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { cpu = "25m", memory = "32Mi" }
            limits   = { cpu = "50m", memory = "64Mi" }
          }
        }
      }

      grafana = {
        admin = {
          existingSecret = kubernetes_secret.grafana_admin.metadata[0].name
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }
        persistence = {
          enabled = true
          size    = var.grafana_storage_size
        }
        resources = var.grafana_resources
      }
    })
  ]

  depends_on = [kubernetes_secret.grafana_admin]
}
