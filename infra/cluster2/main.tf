locals {
  common_tags = {
    Project     = "eks-migration"
    Environment = var.environment
    Cluster     = var.cluster_name
    ManagedBy   = "terraform"
  }
}

# ─── Cluster 1 remote state (for VPC peering + RDS SG update) ───────────────
data "terraform_remote_state" "cluster1" {
  backend = "s3"
  config = {
    bucket = var.tf_state_bucket
    key    = "cluster1/terraform.tfstate"
    region = var.aws_region
  }
}

# ─── VPC ─────────────────────────────────────────────────────────────────────
module "vpc" {
  source       = "../modules/vpc"
  name         = var.cluster_name
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  tags         = local.common_tags
}

# ─── VPC Peering (cluster2 → cluster1) ───────────────────────────────────────
resource "aws_vpc_peering_connection" "to_cluster1" {
  vpc_id      = module.vpc.vpc_id
  peer_vpc_id = data.terraform_remote_state.cluster1.outputs.vpc_id
  auto_accept = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-to-cluster1-peering"
  })
}

# Routes from cluster2 private subnets → cluster1 VPC (for RDS access)
resource "aws_route" "cluster2_to_cluster1" {
  count                     = length(module.vpc.private_route_table_ids)
  route_table_id            = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block    = data.terraform_remote_state.cluster1.outputs.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.to_cluster1.id
}

# Route from cluster1 private subnets → cluster2 VPC
data "aws_route_tables" "cluster1_private" {
  vpc_id = data.terraform_remote_state.cluster1.outputs.vpc_id

  filter {
    name   = "tag:Name"
    values = ["eks-cluster-1-private-rt-*"]
  }
}

resource "aws_route" "cluster1_to_cluster2" {
  for_each                  = toset(data.aws_route_tables.cluster1_private.ids)
  route_table_id            = each.value
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.to_cluster1.id
}

# Allow cluster2 VPC CIDR in the RDS security group
resource "aws_security_group_rule" "rds_allow_cluster2" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = data.terraform_remote_state.cluster1.outputs.rds_security_group_id
  description       = "Allow cluster2 VPC to access RDS"
}

# ─── EKS Cluster ─────────────────────────────────────────────────────────────
module "eks" {
  source          = "../modules/eks"
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  admin_role_arns = var.admin_role_arns
  tags            = local.common_tags
}

# ─── S3 for Velero (shared bucket from cluster1 state) ───────────────────────
locals {
  velero_bucket = data.terraform_remote_state.cluster1.outputs.velero_bucket
}

# ─── Route 53 weighted routing (progressive traffic shift) ───────────────────
module "route53" {
  source                = "../modules/route53"
  zone_name             = var.zone_name
  app_subdomain         = var.app_hostname
  cluster_name          = var.cluster_name
  primary_lb_hostname   = data.terraform_remote_state.cluster1.outputs.rds_host != "" ? var.cluster1_lb_hostname : ""
  secondary_lb_hostname = var.istio_lb_hostname
  primary_weight        = var.cluster1_weight
  secondary_weight      = var.cluster2_weight
  tags                  = local.common_tags
}

# ─── IAM Roles + Pod Identity ────────────────────────────────────────────────
module "iam" {
  source              = "../modules/iam"
  cluster_name        = var.cluster_name
  velero_bucket       = local.velero_bucket
  hosted_zone_id      = module.route53.zone_id
  app_namespace       = "taskmanager"
  app_service_account = "taskmanager"
  app_uploads_bucket  = ""
  tags                = local.common_tags

  depends_on = [module.eks]
}

# ─── Kubernetes Add-ons ───────────────────────────────────────────────────────
module "addons" {
  source = "../modules/addons"

  cluster_name           = module.eks.cluster_name
  aws_region             = var.aws_region
  cluster_endpoint       = module.eks.cluster_endpoint
  cluster_ca_certificate = module.eks.cluster_ca_certificate
  cluster_token          = data.aws_eks_cluster_auth.this.token

  cert_manager_role_arn = module.iam.cert_manager_role_arn
  eso_role_arn          = module.iam.eso_role_arn
  velero_role_arn       = module.iam.velero_role_arn
  velero_bucket         = local.velero_bucket

  hosted_zone_id = module.route53.zone_id
  zone_name      = var.zone_name
  app_hostname   = var.app_hostname
  acme_email     = var.acme_email

  tags = local.common_tags

  depends_on = [module.eks, module.iam]
}

# ─── ArgoCD Application ──────────────────────────────────────────────────────
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
            - values-cluster2.yaml
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
