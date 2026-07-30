# IRSA role for the AWS Load Balancer Controller, plus the controller
# itself, installed via the upstream Helm chart from the "eks" repo
# (https://aws.github.io/eks-charts). The controller watches Ingress/Service
# objects and provisions/updates ALBs & NLBs via the AWS API - it needs an
# IAM identity with EC2/ELBv2 permissions, granted here through IRSA rather
# than node-level IAM so the permission is scoped to this one workload.
module "irsa_alb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "6.6.1" # verified latest as of 2026-07-30 - https://github.com/terraform-aws-modules/terraform-aws-iam/releases

  role_name = "${var.cluster_name}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.region
      vpcId       = var.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.irsa_alb_controller.iam_role_arn
        }
      }

      # Demo-sized; bump for a real multi-tenant cluster.
      replicaCount = 2

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
    })
  ]
}
