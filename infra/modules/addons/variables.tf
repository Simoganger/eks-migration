variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64)"
  type        = string
}

variable "cluster_token" {
  description = "EKS cluster auth token"
  type        = string
  sensitive   = true
}

variable "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager (Route 53 DNS-01)"
  type        = string
}

variable "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  type        = string
}

variable "velero_role_arn" {
  description = "IAM role ARN for Velero"
  type        = string
}

variable "velero_bucket" {
  description = "S3 bucket name for Velero backups"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "zone_name" {
  description = "Route 53 zone name (e.g. navelmountech.com)"
  type        = string
}

variable "app_hostname" {
  description = "Application hostname (e.g. app.navelmountech.com)"
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
