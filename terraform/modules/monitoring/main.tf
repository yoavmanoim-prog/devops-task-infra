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

# EKS's built-in `gp2` StorageClass is unusable on Kubernetes 1.31+: its
# provisioner is the in-tree kubernetes.io/aws-ebs driver, which was removed
# from Kubernetes. It is also not marked default. So this module declares the
# StorageClass it needs, backed by the aws-ebs-csi-driver addon the eks module
# installs, and both PVC specs below reference it BY NAME rather than relying
# on default-StorageClass semantics - a missing default is exactly how this
# failed the first time (PVCs Pending, Helm timing out with a "context
# deadline exceeded" that says nothing about storage).
#
# gp3 over gp2: cheaper per GB, and baseline IOPS/throughput aren't tied to
# volume size.
#
# Scope note: a StorageClass is cluster-wide, so this arguably belongs in a
# dedicated platform unit rather than in `monitoring`. It lives here because
# monitoring is the only PVC consumer today and this module already has a
# configured kubernetes provider; the eks unit deliberately has none, since
# configuring one from the same module that creates the cluster is a
# first-apply ordering trap.
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  # WaitForFirstConsumer so the volume is created in whichever AZ the pod is
  # scheduled into. Note this fixes INITIAL placement only - see the EBS
  # AZ-pinning caveat in infra/README.md.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

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

  # The default is 300s, which this chart does not reliably meet on a small
  # cluster: it installs ~10 workloads plus a large CRD set, and Prometheus
  # and Grafana each have to wait on an EBS volume being provisioned and
  # attached. Exceeding it surfaces as a bare "context deadline exceeded"
  # that names neither the chart nor storage, and leaves a `failed` Helm
  # release behind that blocks the next apply until it's uninstalled by hand.
  timeout = 900

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = var.retention
          resources = var.prometheus_resources
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes      = ["ReadWriteOnce"]
                storageClassName = kubernetes_storage_class.gp3.metadata[0].name
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
          enabled          = true
          size             = var.grafana_storage_size
          storageClassName = kubernetes_storage_class.gp3.metadata[0].name
        }
        resources = var.grafana_resources
      }
    })
  ]

  depends_on = [kubernetes_secret.grafana_admin]
}
