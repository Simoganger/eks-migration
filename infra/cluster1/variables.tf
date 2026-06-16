variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-cluster-1"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_role_arns" {
  description = "IAM role ARNs to grant cluster-admin access"
  type        = list(string)
  default     = []
}

variable "zone_name" {
  description = "Route 53 zone name"
  type        = string
  default     = "navelmountech.com"
}

variable "app_hostname" {
  description = "Application hostname"
  type        = string
  default     = "app.navelmountech.com"
}

variable "acme_email" {
  description = "Email for Let's Encrypt registration"
  type        = string
}

variable "istio_lb_hostname" {
  description = "Istio IngressGateway NLB hostname (set after first apply)"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "taskmanager"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "taskadmin"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ"
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final RDS snapshot on destroy"
  type        = bool
  default     = false
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD to sync from"
  type        = string
  default     = "https://github.com/your-org/eks-migration"
}

variable "app_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}
