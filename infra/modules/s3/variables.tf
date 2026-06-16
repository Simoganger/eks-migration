variable "bucket_name" {
  description = "S3 bucket name for Velero backups"
  type        = string
}

variable "backup_retention_days" {
  description = "Number of days to retain Velero backups"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
