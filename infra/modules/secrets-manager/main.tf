resource "aws_secretsmanager_secret" "db" {
  name                    = "/${var.environment}/taskmanager/db"
  description             = "TaskManager RDS credentials"
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = var.db_host
    port     = tostring(var.db_port)
    dbname   = var.db_name
  })
}
