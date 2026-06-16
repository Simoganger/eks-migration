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
  default     = "eks-cluster-2"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "vpc_cidr" {
  description = "VPC CIDR block (must not overlap with cluster1)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "tf_state_bucket" {
  description = "S3 bucket containing cluster1 Terraform state"
  type        = string
  default     = "eks-migration-tfstate"
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
  description = "Istio IngressGateway NLB hostname for cluster2 (set after first apply)"
  type        = string
  default     = ""
}

variable "cluster1_lb_hostname" {
  description = "Istio IngressGateway NLB hostname for cluster1 (for weighted DNS)"
  type        = string
  default     = ""
}

# Traffic weights — adjust progressively during migration
variable "cluster1_weight" {
  description = "Route 53 weight for cluster1 (decreases during migration)"
  type        = number
  default     = 100
}

variable "cluster2_weight" {
  description = "Route 53 weight for cluster2 (increases during migration)"
  type        = number
  default     = 0
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
