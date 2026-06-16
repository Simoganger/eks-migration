data "aws_route53_zone" "this" {
  name         = var.zone_name
  private_zone = false
}

# ─── Primary DNS record (weighted) ──────────────────────────────────────────
resource "aws_route53_record" "app_primary" {
  count = var.primary_lb_hostname != "" ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.app_subdomain
  type    = "CNAME"

  weighted_routing_policy {
    weight = var.primary_weight
  }

  set_identifier = "${var.cluster_name}-primary"
  ttl            = 60
  records        = [var.primary_lb_hostname]
}

# ─── Secondary DNS record (weighted — used during migration) ────────────────
resource "aws_route53_record" "app_secondary" {
  count = var.secondary_lb_hostname != "" ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.app_subdomain
  type    = "CNAME"

  weighted_routing_policy {
    weight = var.secondary_weight
  }

  set_identifier = "${var.cluster_name}-secondary"
  ttl            = 60
  records        = [var.secondary_lb_hostname]
}

# ─── Health check for primary cluster ───────────────────────────────────────
resource "aws_route53_health_check" "primary" {
  count = var.primary_lb_hostname != "" ? 1 : 0

  fqdn              = var.primary_lb_hostname
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-primary-health-check"
  })
}
