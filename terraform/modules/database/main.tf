# Database Module - RDS PostgreSQL with Multi-Tenant Schema
# Includes Pagila sample data initialization

# Generate random password for RDS
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store database credentials in Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-${var.environment}-db-credentials"
  description             = "RDS PostgreSQL master credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.endpoint
    port     = 5432
    dbname   = var.db_name
  })
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = []  # Will be populated by compute module
    cidr_blocks     = ["10.0.0.0/16"]  # Allow from entire VPC
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine configuration
  engine               = "postgres"
  engine_version       = "16.1"
  instance_class       = var.db_instance_class
  allocated_storage    = 20
  storage_type         = "gp3"
  storage_encrypted    = true
  max_allocated_storage = 100  # Auto-scaling up to 100GB

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period = 7
  backup_window          = "03:00-04:00"  # 3-4 AM UTC
  maintenance_window     = "mon:04:00-mon:05:00"

  # Performance and monitoring
  performance_insights_enabled = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # High availability
  multi_az = var.environment == "production" ? true : false

  # Protection
  deletion_protection = var.environment == "production" ? true : false
  skip_final_snapshot = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Parameter group for multi-tenant optimizations
  parameter_group_name = aws_db_parameter_group.main.name

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}

# Custom parameter group for PostgreSQL
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-postgres-params"
  family = "postgres16"

  # Optimize for multi-tenant workloads
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking > 1 second
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres-params"
  }
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Lambda function to initialize database (Pagila + multi-tenant schema)
resource "aws_lambda_function" "db_init" {
  filename      = "${path.module}/lambda/db_init.zip"
  function_name = "${var.project_name}-${var.environment}-db-init"
  role          = aws_iam_role.lambda_db_init.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300

  environment {
    variables = {
      DB_SECRET_ARN = aws_secretsmanager_secret.db_credentials.arn
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_db_init.id]
  }

  depends_on = [aws_db_instance.main]

  tags = {
    Name = "${var.project_name}-${var.environment}-db-init"
  }
}

# Security group for Lambda
resource "aws_security_group" "lambda_db_init" {
  name_prefix = "${var.project_name}-${var.environment}-lambda-db-init-"
  description = "Security group for database initialization Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "PostgreSQL to RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "HTTPS for Secrets Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-db-init-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_db_init" {
  name = "${var.project_name}-${var.environment}-lambda-db-init"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-db-init"
  }
}

resource "aws_iam_role_policy" "lambda_db_init" {
  name = "${var.project_name}-${var.environment}-lambda-db-init"
  role = aws_iam_role.lambda_db_init.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Outputs
output "db_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "db_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}
