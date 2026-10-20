# HorizontalPodAutoscaler (autoscaling/v2). Every ~15 s it reads pod CPU from
# metrics-server and computes: desired = ceil(current * actualCPU% / target%).
resource "kubernetes_horizontal_pod_autoscaler_v2" "cloudpose_hpa" {
  metadata {
    name   = "cloudpose-hpa"
    labels = { app = var.app_name }
  }

  spec {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.cloudpose.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.target_cpu_percentage
        }
      }
    }

    behavior {
      # Scale up fast: react immediately, at most double the pods every 15 s.
      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 15
        }
      }
      # Scale down slowly: wait 5 min of low load, then remove at most half per minute.
      # Prevents "flapping" when traffic is spiky.
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }
    }
  }
}
