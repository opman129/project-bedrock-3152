resource "aws_security_group" "rds_sg" {
  name        = "project-bedrock-rds-sg"
  description = "Allow database access from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "MySQL from EKS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "project-bedrock-rds-sg"
    Project = "karatu-2025-capstone"
  }
}

resource "aws_db_subnet_group" "bedrock" {
  name = "project-bedrock-db-subnet-group"

  subnet_ids = module.vpc.private_subnets

  tags = {
    Name    = "project-bedrock-db-subnet-group"
    Project = "karatu-2025-capstone"
  }
}

resource "aws_db_instance" "mysql" {
  identifier = "project-bedrock-mysql"

  engine         = "mysql"
  engine_version = "8.0"

  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name = "orders"

  username                    = "admin"
  manage_master_user_password = true

  publicly_accessible = false

  db_subnet_group_name   = aws_db_subnet_group.bedrock.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  skip_final_snapshot       = false
  final_snapshot_identifier = "project-bedrock-mysql-final"

  tags = {
    Project = "karatu-2025-capstone"
  }

  storage_encrypted = true

  backup_retention_period = 0
}

resource "aws_db_instance" "postgres" {
  identifier = "project-bedrock-postgres"

  engine         = "postgres"
  engine_version = "17"

  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name = "retailcatalog"

  username                    = "postgresadmin"
  manage_master_user_password = true

  publicly_accessible = false

  db_subnet_group_name   = aws_db_subnet_group.bedrock.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  skip_final_snapshot       = false
  final_snapshot_identifier = "project-bedrock-postgres-final"

  tags = {
    Project = "karatu-2025-capstone"
  }

  storage_encrypted = true

  backup_retention_period = 0
}

resource "aws_dynamodb_table" "products" {
  name         = "project-bedrock-products"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Project = "karatu-2025-capstone"
  }
}