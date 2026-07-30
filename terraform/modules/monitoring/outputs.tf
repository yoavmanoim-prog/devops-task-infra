output "namespace" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}

output "grafana_admin_secret_name" {
  value = kubernetes_secret.grafana_admin.metadata[0].name
}
