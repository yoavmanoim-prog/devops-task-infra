# ArgoCD, installed via the upstream Helm chart, configured for:
#  - GitHub OAuth SSO through Dex (no local admin password used day-to-day)
#  - RBAC: your GitHub username -> role:admin, every other authenticated
#    GitHub user -> role:readonly (ArgoCD's built-in policy.default)
#  - exposure via an AWS NLB Service (L4, TLS terminated by ArgoCD itself -
#    no ACM cert/domain required for this demo; see repo README for the
#    documented-but-not-implemented path to a real ACM-backed hostname)
#  - one bootstrap "app of apps" Application pointing at this cluster's
#    folder in the gitops repo, which in turn defines this env's AppProject
#    and the actual workload Application

# The namespace is created explicitly rather than leaving it to the Helm
# release's create_namespace, because the Dex OAuth secret below has to exist
# in this namespace BEFORE the chart installs - and helm_release depends_on
# that secret. Letting Helm own the namespace makes those two requirements
# circular, and the apply fails with `namespaces "argocd" not found`. Same
# pattern the monitoring module already uses.
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret" "argocd_github_oauth" {
  metadata {
    name      = "argocd-github-oauth"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/part-of" = "argocd"
    }
  }

  data = {
    clientID     = var.github_oauth_client_id
    clientSecret = var.github_oauth_client_secret
  }

  type = "Opaque"
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false # owned by kubernetes_namespace.argocd above

  values = [
    yamlencode({
      global = {
        domain = var.argocd_external_url != "" ? var.argocd_external_url : "argocd.${var.env}.local"
      }

      configs = {
        cm = {
          url = var.argocd_external_url != "" ? "https://${var.argocd_external_url}" : ""

          "dex.config" = yamlencode({
            connectors = [
              {
                type = "github"
                id   = "github"
                name = "GitHub"
                config = {
                  clientID     = "$argocd-github-oauth:clientID"
                  clientSecret = "$argocd-github-oauth:clientSecret"
                }
              }
            ]
          })
        }

        rbac = {
          "policy.default" = "role:readonly"
          "policy.csv"     = "g, ${var.admin_github_username}, role:admin"
        }
      }

      server = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          }
        }

        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "250m", memory = "256Mi" }
        }
      }

      controller = {
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      redis-ha = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_secret.argocd_github_oauth]
}

# Bootstrap "app of apps": the ONLY Application Terraform ever creates
# directly. It lives in the default project (which always exists, avoiding
# a chicken-and-egg problem with the env-scoped AppProject(s) that this same
# sync wave creates) and just points at this cluster's folder in the gitops
# repo. Everything else - AppProject(s), the real workload Application(s),
# namespaces/quotas/RBAC - is defined as YAML in that repo and reconciled by
# ArgoCD from here on, not re-applied by Terraform. For the dev cluster,
# apps/dev/ contains an ApplicationSet (list generator over [dev, staging])
# so this one bootstrap Application fans out to both namespaces; for prod,
# apps/prod/ is a single manual-sync Application for the production ns.
resource "kubernetes_manifest" "bootstrap_app_of_apps" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${var.env}-root"
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = "HEAD"
        path           = "apps/${var.env}"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
