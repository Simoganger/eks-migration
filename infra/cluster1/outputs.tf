output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "rds_host" {
  value = module.rds.db_host
}

output "rds_port" {
  value = module.rds.db_port
}

output "velero_bucket" {
  value = module.s3_velero.bucket_name
}

output "secret_arn" {
  value = module.secrets_manager.secret_arn
}

output "route53_zone_id" {
  value = module.route53.zone_id
}

output "rds_security_group_id" {
  value = module.rds.security_group_id
}
