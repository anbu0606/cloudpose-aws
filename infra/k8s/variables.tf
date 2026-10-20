variable "kubeconfig_path" {
  type        = string
  default     = "~/.kube/config"
  description = "Kubeconfig file written by kind"
}

variable "kube_context" {
  type        = string
  default     = "kind-cloudpose"
  description = "Kubeconfig context to deploy into (kind names it kind-<cluster>)"
}

variable "app_name" {
  type        = string
  default     = "cloudpose"
  description = "Name/label of the application"
}

variable "image" {
  type        = string
  default     = "cloudpose:0.2.0"
  description = "Container image. Built locally and loaded into kind with `kind load docker-image`"
}

variable "container_port" {
  type    = number
  default = 60007
}

variable "node_port" {
  type        = number
  default     = 30006
  description = "NodePort exposed on every node (mapped to localhost:30006 by kind-config.yaml)"
}

variable "min_replicas" {
  type    = number
  default = 2
}

variable "max_replicas" {
  type        = number
  default     = 8
  description = "HPA ceiling. Lower it (e.g. 5) if your laptop has <16 GB RAM"
}

variable "target_cpu_percentage" {
  type        = number
  default     = 70
  description = "HPA target: average CPU as % of each pod's CPU *request*"
}

variable "kps_chart_version" {
  type        = string
  description = "kube-prometheus-stack chart version (pin it; get it from `helm search repo`)"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Set via the TF_VAR_grafana_admin_password env var, never in a file"
}
