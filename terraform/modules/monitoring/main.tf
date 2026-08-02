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

      # Alert DELIVERY. Without the config below, kube-prometheus-stack's
      # default routes everything to a receiver literally named "null" - so all
      # ~100 bundled rules evaluate, fire, and are discarded. Monitoring that
      # cannot tell anyone anything: the dashboards look healthy because nobody
      # is on the other end.
      #
      # SNS rather than Slack/PagerDuty because it needs no third-party secret
      # in this repo, and Alertmanager authenticates with IRSA - the same
      # web-identity federation the app and the ALB controller use, so there is
      # still no long-lived AWS credential anywhere in the cluster. Alertmanager
      # signs SNS calls with SigV4 via the AWS SDK's default chain, which picks
      # up the projected service-account token.
      alertmanager = merge(
        {
          alertmanagerSpec = {
            resources = {
              requests = { cpu = "25m", memory = "32Mi" }
              limits   = { cpu = "50m", memory = "64Mi" }
            }
          }
        },
        var.enable_alert_delivery ? {
          # IRSA. Note this is alertmanager.serviceAccount, NOT
          # alertmanager.alertmanagerSpec.serviceAccount - the latter is
          # accepted by Helm and silently ignored, leaving the pod with no AWS
          # credentials and every SNS publish failing on auth. Verify with:
          #   kubectl get sa kube-prometheus-stack-alertmanager -n monitoring \
          #     -o jsonpath='{.metadata.annotations}'
          serviceAccount = {
            annotations = {
              "eks.amazonaws.com/role-arn" = aws_iam_role.alertmanager[0].arn
            }
          }
        } : {},
        var.enable_alert_delivery ? {
          config = {
            route = {
              # group_by/group_wait keep a burst of related alerts to one
              # notification rather than one per firing series.
              group_by        = ["alertname", "namespace"]
              group_wait      = "30s"
              group_interval  = "5m"
              repeat_interval = "12h"
              receiver        = "sns"
              routes = [
                # Watchdog fires constantly BY DESIGN - it is the heartbeat that
                # proves the alert pipeline is alive. Paging on it would be
                # noise, so it stays on the null receiver.
                { matchers = ["alertname = Watchdog"], receiver = "null" },
              ]
            }
            receivers = [
              { name = "null" },
              {
                name = "sns"
                sns_configs = [{
                  topic_arn = aws_sns_topic.alerts[0].arn
                  sigv4     = { region = var.region }
                  subject   = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }} ({{ .Alerts | len }})"
                  message   = "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}\n\n{{ end }}"
                }]
              },
            ]
          }
        } : {}
      )

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

# ---------------------------------------------------------------------------
# Alert delivery
#
# All of this exists so that a fired alert reaches a person. Before it, the
# chart's default Alertmanager route pointed every alert at a receiver named
# "null": the rules evaluated, the alerts fired, and nothing happened. Nothing
# in the cluster reported an error, because discarding alerts IS the configured
# behaviour - the same silent-no-op shape as a NetworkPolicy nothing enforces.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  count = var.enable_alert_delivery ? 1 : 0

  name = "${var.cluster_name}-alerts"
  tags = var.tags
}

# Optional, and the topic is useful without it (other subscribers, or a Lambda
# later). But note AWS requires the recipient to click a confirmation link -
# until they do, publishes succeed and are delivered nowhere.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.enable_alert_delivery && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# IRSA for Alertmanager. Written out rather than using the shared
# iam-role-for-service-accounts module because that module's attach_*_policy
# flags cover a fixed set of well-known workloads and SNS is not one of them.
#
# StringEquals on both sub and aud, no wildcards: only the
# kube-prometheus-stack-alertmanager ServiceAccount in this namespace can
# assume it. A StringLike over `system:serviceaccount:*:*` would let any pod on
# the cluster publish alerts, which is the same wildcard mistake the GitHub
# OIDC role deliberately avoids.
data "aws_iam_policy_document" "alertmanager_assume_role" {
  count = var.enable_alert_delivery ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.namespace}:kube-prometheus-stack-alertmanager"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "alertmanager_publish" {
  count = var.enable_alert_delivery ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts[0].arn] # this topic only, not sns:*
  }
}

resource "aws_iam_role" "alertmanager" {
  count = var.enable_alert_delivery ? 1 : 0

  name               = "${var.cluster_name}-alertmanager"
  assume_role_policy = data.aws_iam_policy_document.alertmanager_assume_role[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "alertmanager_publish" {
  count = var.enable_alert_delivery ? 1 : 0

  name   = "sns-publish"
  role   = aws_iam_role.alertmanager[0].id
  policy = data.aws_iam_policy_document.alertmanager_publish[0].json
}
