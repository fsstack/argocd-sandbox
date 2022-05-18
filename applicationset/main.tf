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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "3.15.0"
    }
  }
}


provider "cloudflare" {}

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
    mgmt = {},
    dev  = {},
    prod = {}
  }
  argocd_values = {
    server = {
      service = {
        type = "NodePort"
      }
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

data "cloudflare_zone" "this" {
  name = "fsstack.org"
}

resource "cloudflare_record" "argocd" {
  zone_id = data.cloudflare_zone.this.zone_id
  name    = "argocd"
  value   = data.digitalocean_droplet.mgmt.ipv4_address
  type    = "A"
  ttl     = 60
}

output "argocd_url" {
  value = "https://${cloudflare_record.argocd.hostname}:30443"
}
