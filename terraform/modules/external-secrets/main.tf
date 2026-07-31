# IRSA role for the External Secrets Operator (ESO) controller, the
# controller itself via the upstream Helm chart, and one ClusterSecretStore
# so every namespace on this cluster can declare ExternalSecret resources
# backed by AWS Secrets Manager without each namespace needing its own
# IAM identity. `secret_arns` is deliberately per-environment (passed in by
# the caller) so a compromised dev pod's ExternalSecret can't be pointed at
# a prod secret ARN and succeed.
module "irsa_external_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1" # verified latest as of 2026-07-30 - https://github.com/terraform-aws-modules/terraform-aws-iam/releases

  name = "${var.cluster_name}-external-secrets"

  # NOTE ON VERIFICATION: attach_external_secrets_policy + the
  # external_secrets_*_arns inputs are documented on this module's current
  # registry page as of 2026-07-30. Re-check against the pinned version's
  # docs before apply, same as every other module in this repo.
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = var.secret_arns
  external_secrets_ssm_parameter_arns   = var.secret_arns

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:external-secrets"]
    }
  }

  tags = var.tags
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "external-secrets"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.irsa_external_secrets.arn
        }
      }

      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "100m", memory = "128Mi" }
      }
    })
  ]
}

# One ClusterSecretStore per cluster, authenticated via the controller's own
# IRSA role (var.secret_arns already scopes what it can read) rather than a
# separate identity per namespace - simpler to reason about for a
# demonstration cluster with a handful of namespaces.
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = var.namespace
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}
