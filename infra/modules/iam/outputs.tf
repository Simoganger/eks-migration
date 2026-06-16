output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}

output "velero_role_arn" {
  value = aws_iam_role.velero.arn
}

output "cert_manager_role_arn" {
  value = aws_iam_role.cert_manager.arn
}
