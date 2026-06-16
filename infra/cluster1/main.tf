locals {
  common_tags = {
    Project     = "eks-migration"
    Environment = var.environment
    Cluster     = var.cluster_name
    ManagedBy   = "terraform"
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

# ─── S3 bucket for Velero ────────────────────────────────────────────────────
module "s3_velero" {
  source                = "../modules/s3"
  bucket_name           = "${var.cluster_name}-velero-backups"
  backup_retention_days = 90
  tags                  = local.common_tags
}

# ─── RDS PostgreSQL ──────────────────────────────────────────────────────────
module "rds" {
  source              = "../modules/rds"
  identifier          = "${var.cluster_name}-postgres"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  allowed_cidr_blocks = [var.vpc_cidr]
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = var.db_password
  instance_class      = var.rds_instance_class
  multi_az            = var.rds_multi_az
  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = var.rds_skip_final_snapshot
  tags                = local.common_tags
}

# ─── AWS Secrets Manager ─────────────────────────────────────────────────────
module "secrets_manager" {
  source      = "../modules/secrets-manager"
  environment = var.environment
  db_username = var.db_username
  db_password = var.db_password
  db_host     = module.rds.db_host
  db_port     = module.rds.db_port
  db_name     = module.rds.db_name
  tags        = local.common_tags
}

# ─── Route 53 ────────────────────────────────────────────────────────────────
module "route53" {
  source              = "../modules/route53"
  zone_name           = var.zone_name
  app_subdomain       = var.app_hostname
  cluster_name        = var.cluster_name
  primary_lb_hostname = var.istio_lb_hostname
  primary_weight      = 100
  tags                = local.common_tags
}

# ─── IAM Roles + Pod Identity ────────────────────────────────────────────────
module "iam" {
  source              = "../modules/iam"
  cluster_name        = var.cluster_name
  velero_bucket       = module.s3_velero.bucket_name
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
  velero_bucket         = module.s3_velero.bucket_name

  hosted_zone_id = module.route53.zone_id
  zone_name      = var.zone_name
  app_hostname   = var.app_hostname
  acme_email     = var.acme_email

  tags = local.common_tags

  depends_on = [module.eks, module.iam]
}
