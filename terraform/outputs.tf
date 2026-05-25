output "vpc_id" {
  value = module.vpc.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = var.aws_region
}

output "mysql_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "postgres_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.products.name
}

output "mysql_secret_arn" {
  value = try(aws_db_instance.mysql.master_user_secret[0].secret_arn, null)
}

output "postgres_secret_arn" {
  value = try(aws_db_instance.postgres.master_user_secret[0].secret_arn, null)
}
