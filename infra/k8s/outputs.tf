output "app_url" {
  value       = "http://localhost:${var.node_port}"
  description = "CloudPose via the kind NodePort mapping"
}

output "deployment_name" {
  value = kubernetes_deployment.cloudpose.metadata[0].name
}

output "hpa_name" {
  value = kubernetes_horizontal_pod_autoscaler_v2.cloudpose_hpa.metadata[0].name
}

output "grafana_cmd" {
  value = "kubectl -n monitoring port-forward svc/kps-grafana 3000:80   ->  http://localhost:3000 (user: admin)"
}

output "prometheus_cmd" {
  value = "kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090   ->  http://localhost:9090"
}
