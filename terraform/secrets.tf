resource "aws_secretsmanager_secret" "mysql" {
  name = "project-bedrock/mysql"

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_secretsmanager_secret_version" "mysql" {
  secret_id = aws_secretsmanager_secret.mysql.id

  secret_string = jsonencode({
    username = "admin"
    password = "ChangeThisPassword123!"
    engine   = "mysql"
    host     = aws_db_instance.mysql.address
    port     = 3306
    dbname   = "orders"
  })
}

resource "aws_secretsmanager_secret" "postgres" {
  name = "project-bedrock/postgres"

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id

  secret_string = jsonencode({
    username = "postgresadmin"
    password = "ChangeThisPassword123!"
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = "retailcatalog"
  })
}