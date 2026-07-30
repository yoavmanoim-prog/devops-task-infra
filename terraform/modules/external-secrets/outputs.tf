output "irsa_role_arn" {
  value = module.irsa_external_secrets.iam_role_arn
}

output "cluster_secret_store_name" {
  value = kubernetes_manifest.cluster_secret_store.manifest.metadata.name
}
