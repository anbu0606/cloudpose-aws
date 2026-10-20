# kube-prometheus-stack = Prometheus Operator + Prometheus + Alertmanager + Grafana
# + node-exporter + kube-state-metrics, installed as ONE Helm release.
# Managing the Helm release from Terraform ("Helm via Terraform") means the app and
# its monitoring are created, versioned and destroyed by the same `terraform apply`.
resource "helm_release" "kube_prometheus_stack" {
  name             = "kps"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kps_chart_version
  namespace        = "monitoring"
  create_namespace = true

  values = [file("${path.module}/values/kube-prometheus-stack.yaml")]

  # Passed separately and marked sensitive so it never prints in plan output.
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  timeout = 900 # first install pulls ~1 GB of images
  wait    = true
}

# Grafana's sidecar watches for ConfigMaps labelled grafana_dashboard=1 and loads
# them as dashboards automatically -> "dashboards as code".
resource "kubernetes_config_map" "cloudpose_dashboard" {
  metadata {
    name      = "cloudpose-dashboard"
    namespace = "monitoring"
    labels    = { grafana_dashboard = "1" }
  }

  data = {
    "cloudpose.json" = file("${path.module}/dashboards/cloudpose.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
