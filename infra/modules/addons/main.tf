locals {
  istio_namespace        = "istio-system"
  argocd_namespace       = "argocd"
  eso_namespace          = "external-secrets"
  velero_namespace       = "velero"
  cert_manager_namespace = "cert-manager"
  taskmanager_namespace  = "taskmanager"
}

# ─── cert-manager ────────────────────────────────────────────────────────────
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.2"
  namespace        = local.cert_manager_namespace
  create_namespace = true
  wait             = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.cert_manager_role_arn
  }
}

# ─── ClusterIssuer (Let's Encrypt via Route 53 DNS-01) ───────────────────────
resource "kubectl_manifest" "letsencrypt_clusterissuer" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        email: ${var.acme_email}
        server: https://acme-v02.api.letsencrypt.org/directory
        privateKeySecretRef:
          name: letsencrypt-prod-account-key
        solvers:
          - dns01:
              route53:
                region: ${var.aws_region}
                hostedZoneID: ${var.hosted_zone_id}
  YAML

  depends_on = [helm_release.cert_manager]
}

# ─── TLS Certificate ─────────────────────────────────────────────────────────
resource "kubectl_manifest" "app_certificate" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: taskmanager-tls
      namespace: ${local.istio_namespace}
    spec:
      secretName: taskmanager-tls
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer
      dnsNames:
        - ${var.app_hostname}
        - "*.${var.zone_name}"
  YAML

  depends_on = [kubectl_manifest.letsencrypt_clusterissuer]
}

# ─── Istio ────────────────────────────────────────────────────────────────────
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = "1.24.2"
  namespace        = local.istio_namespace
  create_namespace = true
  wait             = true
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = "1.24.2"
  namespace  = local.istio_namespace
  wait       = true

  set {
    name  = "pilot.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "pilot.resources.requests.memory"
    value = "128Mi"
  }

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = "1.24.2"
  namespace  = local.istio_namespace
  wait       = true

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  depends_on = [helm_release.istiod]
}

# ─── Namespace with Istio injection ──────────────────────────────────────────
resource "kubectl_manifest" "taskmanager_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${local.taskmanager_namespace}
      labels:
        istio-injection: enabled
  YAML

  depends_on = [helm_release.istiod]
}

# ─── External Secrets Operator ────────────────────────────────────────────────
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.7"
  namespace        = local.eso_namespace
  create_namespace = true
  wait             = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.eso_role_arn
  }
}

# ─── ClusterSecretStore (AWS Secrets Manager) ────────────────────────────────
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: aws-secrets-manager
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: ${local.eso_namespace}
  YAML

  depends_on = [helm_release.external_secrets]
}

# ─── ArgoCD ──────────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.3"
  namespace        = local.argocd_namespace
  create_namespace = true
  wait             = true

  values = [<<-YAML
    server:
      service:
        type: ClusterIP
    configs:
      params:
        server.insecure: true
    repoServer:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
    applicationSet:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
  YAML
  ]
}

# ─── Velero ──────────────────────────────────────────────────────────────────
resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = "8.1.0"
  namespace        = local.velero_namespace
  create_namespace = true
  wait             = true

  values = [<<-YAML
    serviceAccount:
      server:
        annotations:
          eks.amazonaws.com/role-arn: ${var.velero_role_arn}
    configuration:
      backupStorageLocation:
        - name: default
          provider: aws
          bucket: ${var.velero_bucket}
          config:
            region: ${var.aws_region}
      volumeSnapshotLocation:
        - name: default
          provider: aws
          config:
            region: ${var.aws_region}
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.10.0
        volumeMounts:
          - mountPath: /target
            name: plugins
    schedules:
      daily-backup:
        disabled: false
        schedule: "0 2 * * *"
        template:
          ttl: "720h"
          includedNamespaces:
            - taskmanager
  YAML
  ]
}
