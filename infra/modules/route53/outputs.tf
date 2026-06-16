output "zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "zone_name" {
  value = data.aws_route53_zone.this.name
}
