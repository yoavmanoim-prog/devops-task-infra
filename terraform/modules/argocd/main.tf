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

          # `scopes` controls which JWT claims ArgoCD matches policy.csv
          # subjects against. The chart's default is [groups] ONLY, which
          # silently breaks this policy: with the Dex GitHub connector,
          # `groups` is populated from GitHub org/team membership, and
          # admin_github_username is a personal account with no orgs - so it
          # matched nothing and the admin fell through to policy.default
          # (role:readonly), able to view everything but not sync anything.
          #
          # preferred_username is what Dex sets to the GitHub login, so adding
          # it makes the `g, <username>, role:admin` line above actually
          # resolve. groups is kept first so org/team-based rules still work
          # if this is ever pointed at a real organisation.
          "scopes" = "[groups, preferred_username]"
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

# AppProject for the bootstrap Application below.
#
# That Application used to run in ArgoCD's built-in `default` project, whose
# defaults are destinations `*/*`, sourceRepos `*` and clusterResourceWhitelist
# `*/*` - i.e. deploy anything, anywhere, from any repo. The env-scoped
# projects (dev/prod, defined in the gitops repo) are properly restricted, but
# the root Application that CREATES them sat outside those restrictions, so the
# isolation could be bypassed by whatever the root was pointed at.
#
# The original comment said `default` avoided a chicken-and-egg with the
# projects created in the same sync wave. That reasoning only applies to
# projects ArgoCD creates - Terraform can create this one directly, before the
# Application that references it, so there is no cycle. depends_on makes the
# ordering explicit because ArgoCD rejects an Application naming a project that
# does not yet exist.
#
# Scoped to exactly what the root actually does, confirmed against the live
# cluster (`kubectl get application <env>-root -o jsonpath='{.status.resources}'`):
# it manages an AppProject, an Application and an ApplicationSet - three
# NAMESPACED argoproj.io objects in the argocd namespace, nothing cluster-scoped.
resource "kubernetes_manifest" "bootstrap_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform"
      namespace = var.namespace
    }
    spec = {
      description  = "Bootstrap app-of-apps only. Deliberately narrower than the default project it replaces."
      sourceRepos  = [var.gitops_repo_url]
      destinations = [{ server = "https://kubernetes.default.svc", namespace = var.namespace }]
      # Empty on purpose: the root creates no cluster-scoped resources. The
      # Namespace objects come from the platform Application, which runs under
      # the env-scoped project and has its own whitelist for them.
      clusterResourceWhitelist   = []
      namespaceResourceWhitelist = [{ group = "argoproj.io", kind = "*" }]
    }
  }

  depends_on = [helm_release.argocd]
}

# Bootstrap "app of apps": the ONLY Application Terraform ever creates
# directly. It points at this cluster's folder in the gitops repo; everything
# else - AppProject(s), the real workload Application(s), namespaces/quotas/RBAC
# - is defined as YAML in that repo and reconciled by ArgoCD from here on, not
# re-applied by Terraform. For the dev cluster, apps/dev/ contains an
# ApplicationSet (list generator over [dev, staging]) so this one bootstrap
# Application fans out to both namespaces; for prod, apps/prod/ is a single
# manual-sync Application for the production ns.
resource "kubernetes_manifest" "bootstrap_app_of_apps" {

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${var.env}-root"
      namespace = var.namespace
    }
    spec = {
      project = kubernetes_manifest.bootstrap_project.manifest.metadata.name
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

  # The project too, not just the chart: ArgoCD rejects an Application that
  # names a project which does not exist yet.
  depends_on = [kubernetes_manifest.bootstrap_project]
}
