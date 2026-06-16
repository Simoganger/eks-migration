variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "taskmanager"
}

variable "app_service_account" {
  description = "Kubernetes service account name for the application"
  type        = string
  default     = "taskmanager"
}

variable "app_uploads_bucket" {
  description = "S3 bucket name for app file uploads (not used in MVP — placeholder)"
  type        = string
  default     = ""
}

variable "velero_bucket" {
  description = "S3 bucket name for Velero backups"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for cert-manager DNS-01 challenge"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
