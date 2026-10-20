resource "kubernetes_deployment" "cloudpose" {
  metadata {
    name   = "cloudpose-deployment"
    labels = { app = var.app_name }
  }

  spec {
    # Initial count only. After creation the HPA owns this number (see lifecycle below).
    replicas = var.min_replicas

    selector {
      match_labels = { app = var.app_name }
    }

    # Rolling update: start 1 new pod before killing an old one, never drop below desired.
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }

    template {
      metadata {
        labels = { app = var.app_name }
      }

      spec {
        # Spread replicas across the 2 worker nodes instead of piling onto one.
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = { app = var.app_name }
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
        }

        container {
          name  = var.app_name
          image = var.image
          # The image only exists inside the kind nodes (we loaded it), not in a registry.
          # "Always" would try to pull from Docker Hub and fail with ErrImagePull.
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = var.container_port
          }

          # requests = what the scheduler reserves and what HPA % is measured against.
          # limits   = hard ceiling (CPU is throttled, memory over limit = OOMKilled).
          # Measured: ~420 MB RSS idle with TensorFlow loaded.
          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          # Readiness: "send me traffic?" Fails -> pod removed from the Service, not restarted.
          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            failure_threshold     = 3
          }

          # Liveness: "am I stuck?" Fails -> kubelet restarts the container.
          # Generous timings so a busy pod under load isn't killed by mistake.
          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 20
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 5
          }
        }
      }
    }
  }

  # Without this, every `terraform apply` would reset replicas back to min_replicas,
  # fighting the HPA mid-load. Terraform owns the spec; the HPA owns the count.
  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}
