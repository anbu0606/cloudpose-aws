terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17" # 3.x changed the provider block syntax; stay on 2.x
    }
  }

  # Track B moves this to: backend "s3" { ... } with DynamoDB locking.
  # Until then state is a local terraform.tfstate file (git-ignored).
}

# Both providers read the kubeconfig that `kind create cluster` writes, and are
# pinned to the kind context so a stray `terraform apply` can never hit another cluster.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
