# ApplicationSet Demo
Place to test out ArgoCD ApplicationSet for deploying k8s addons to multiple clusters.  

Using Terraform to create 3 k8s clusters (mgmt, dev, and prod) in DigitalOcean (DO), deploy ArgoCD to the `mgmt` cluster using the ArgoCD helm chart and adding the `dev` and `prod` clusters.
