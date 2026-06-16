resource "kubectl_manifest" "argocd_project" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: taskmanager
      namespace: argocd
    spec:
      description: "TaskManager application project"
      sourceRepos:
        - "*"
      destinations:
        - namespace: taskmanager
          server: https://kubernetes.default.svc
      clusterResourceWhitelist:
        - group: ""
          kind: Namespace
        - group: "cert-manager.io"
          kind: Certificate
        - group: "networking.istio.io"
          kind: Gateway
      namespaceResourceWhitelist:
        - group: "*"
          kind: "*"
  YAML

  depends_on = [module.addons]
}

resource "kubectl_manifest" "argocd_app" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: taskmanager
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: taskmanager
      source:
        repoURL: ${var.git_repo_url}
        targetRevision: main
        path: helm/taskmanager
        helm:
          valueFiles:
            - values.yaml
          parameters:
            - name: image.tag
              value: ${var.app_image_tag}
      destination:
        server: https://kubernetes.default.svc
        namespace: taskmanager
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
  YAML

  depends_on = [kubectl_manifest.argocd_project]
}
