variable "zone_name" {
  description = "Route 53 hosted zone name (e.g. navelmountech.com)"
  type        = string
}

variable "app_subdomain" {
  description = "Full subdomain for the application (e.g. app.navelmountech.com)"
  type        = string
}

variable "cluster_name" {
  description = "Cluster identifier used in Route 53 set_identifier"
  type        = string
}

variable "primary_lb_hostname" {
  description = "Hostname of the primary cluster load balancer"
  type        = string
  default     = ""
}

variable "secondary_lb_hostname" {
  description = "Hostname of the secondary cluster load balancer (used during migration)"
  type        = string
  default     = ""
}

variable "primary_weight" {
  description = "Route 53 weight for the primary cluster (0-255)"
  type        = number
  default     = 100
}

variable "secondary_weight" {
  description = "Route 53 weight for the secondary cluster (0-255)"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
