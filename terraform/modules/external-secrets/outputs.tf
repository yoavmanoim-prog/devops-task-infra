output "irsa_role_arn" {
  value = module.irsa_external_secrets.arn
}

output "cluster_secret_store_name" {
  value = kubernetes_manifest.cluster_secret_store.manifest.metadata.name
}
