terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.19.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.5.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.2.3"
    }
  }
}

provider "local" {}

provider "digitalocean" {}

provider "helm" {
  alias = "mgmt"
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.this["mgmt"].endpoint
    token                  = digitalocean_kubernetes_cluster.this["mgmt"].kube_config[0].token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.this["mgmt"].kube_config[0].cluster_ca_certificate)
  }
}

locals {
  clusters = {
    mgmt = {
      prometheus_operator_version = "v0.49.0"
      node_exporter_chart_version = "3.0.0"
    },
    foo = {
      prometheus_operator_version = "v0.50.0"
      node_exporter_chart_version = "3.2.0"
    },
    bar = {
      prometheus_operator_version = "v0.50.0"
      node_exporter_chart_version = "3.0.0"
    },
    # baz  = {
    #         prometheus_operator_version = "v0.50.0"
    #   node_exporter_chart_version = "3.2.0"
    # }
  }
  cluster_configs = {
    for k, v in digitalocean_kubernetes_cluster.this : k => {
      cluster = {
        name   = v.name != "mgmt" ? v.name : "in-cluster"
        server = v.name != "mgmt" ? v.endpoint : "https://kubernetes.default.svc"
      }
      node_exporter = {
        chart_version = local.clusters[v.name].node_exporter_chart_version
      }
      prometheus_operator = {
        version = local.clusters[v.name].prometheus_operator_version
      }
    }
  }
  argocd_values = {
    server = {
      service = {
        type = "NodePort"
      }
      additionalApplications = [
        {
          name      = "parent-app"
          namespace = "argo-cd"
          project   = "default"
          source = {
            repoURL        = "https://github.com/fsstack/argocd-sandbox.git"
            targetRevision = "HEAD"
            path           = "applicationsets"
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argo-cd"
          }
          syncPolicy = {
            automated = {}
          }
        }
      ]
    }
    configs = {
      secret = {
        argocdServerAdminPassword = "$2a$12$gzNKmK5WOyTEzvl0tPbQk.X37aN38cOYCZGnc1J7i0CpE.amQvtDC"
      }
      clusterCredentials = [for i in digitalocean_kubernetes_cluster.this : {
        name   = i.name,
        server = i.endpoint,
        config = {
          bearerToken = i.kube_config[0].token
          tlsClientConfig = {
            insecure = false
            caData   = i.kube_config[0].cluster_ca_certificate
          }
        }
        }
        if i.name != "mgmt"
      ]
    }
  }
}

resource "digitalocean_kubernetes_cluster" "this" {
  for_each = local.clusters
  name     = each.key
  region   = "sfo3"
  version  = "1.22.8-do.1"
  node_pool {
    name       = "default"
    size       = "s-1vcpu-2gb"
    node_count = 1
  }
}

resource "helm_release" "argocd" {
  provider         = helm.mgmt
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argo-cd"
  create_namespace = true
  values           = [yamlencode(local.argocd_values)]
  depends_on = [
    digitalocean_kubernetes_cluster.this,
  ]
}

data "digitalocean_droplet" "mgmt" {
  id = digitalocean_kubernetes_cluster.this["mgmt"].node_pool[0].nodes[0].droplet_id
}

resource "local_file" "kubeconfig" {
  for_each        = digitalocean_kubernetes_cluster.this
  filename        = "${path.module}/kubeconfig-${each.key}"
  content         = each.value.kube_config.0.raw_config
  file_permission = 0600
}

resource "local_file" "cluster_config" {
  for_each        = local.cluster_configs
  filename        = "${path.module}/../cluster-config/${each.value.cluster.name}/config.json"
  content         = jsonencode(each.value)
  file_permission = 0600
  lifecycle {
    ignore_changes = [
      content
    ]
  }
}

output "argocd_url" {
  value = "https://${data.digitalocean_droplet.mgmt.ipv4_address}:30443"
}
