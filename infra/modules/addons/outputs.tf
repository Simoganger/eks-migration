output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "istio_ingress_namespace" {
  value = helm_release.istio_ingress.namespace
}
