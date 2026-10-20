# NodePort: opens the same port on every node and load-balances to ready pods.
# Flow: localhost:30006 -> kind control-plane container :30006 -> kube-proxy -> a pod :60007
resource "kubernetes_service" "cloudpose" {
  metadata {
    name   = "cloudpose-service"
    labels = { app = var.app_name }
  }

  spec {
    type     = "NodePort"
    selector = { app = var.app_name }

    port {
      name        = "http"
      port        = var.container_port
      target_port = var.container_port
      node_port   = var.node_port
      protocol    = "TCP"
    }
  }
}
