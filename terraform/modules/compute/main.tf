# Compute Module - ECS Fargate Cluster for OpenClaw Agents
# Supports multi-tenant deployment with task-level isolation

# ECR Repository for OpenClaw Docker Images
resource "aws_ecr_repository" "openclaw" {
  name                 = "${var.project_name}-${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr"
  }
}

# ECR Lifecycle Policy (keep last 10 images)
resource "aws_ecr_lifecycle_policy" "openclaw" {
  repository = aws_ecr_repository.openclaw.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/aws/ecs/${var.project_name}-${var.environment}/exec"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-exec-logs"
  }
}

resource "aws_cloudwatch_log_group" "openclaw_agents" {
  name              = "/aws/ecs/${var.project_name}-${var.environment}/agents"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-agent-logs"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-${var.environment}-ecs-tasks-"
  description = "Security group for ECS tasks running OpenClaw agents"
  vpc_id      = var.vpc_id

  # Allow outbound HTTPS (for Bedrock API, OAuth, web scraping)
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTP (for web scraping)
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound PostgreSQL (to RDS)
  egress {
    description = "PostgreSQL to RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow outbound DNS
  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for ECS Task Execution (used by ECS service to pull images, write logs)
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-execution"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for pulling secrets
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = [
          var.db_secret_arn,
          "arn:aws:secretsmanager:*:*:secret:/${var.project_name}/*"
        ]
      }
    ]
  })
}

# ECS Task Execution Role (for pulling images, reading secrets)
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-${var.environment}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-execution-role"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy for reading database password from Secrets Manager
resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.db_password_secret_arn
      }
    ]
  })
}

# IAM Role for ECS Tasks (used by containers at runtime)
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task"
  }
}

# Policy for tasks to access AWS services
resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.agent_data_bucket}/*",
          "arn:aws:s3:::${var.agent_data_bucket}"
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = ["$${aws:userid}/*"]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:/${var.project_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.openclaw_agents.arn}:*"
      }
    ]
  })
}

# ECS Task Definition Template (for Butler agent)
resource "aws_ecs_task_definition" "butler_template" {
  family                   = "${var.project_name}-${var.environment}-butler"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"   # 0.5 vCPU
  memory                   = "1024"  # 1 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "openclaw-butler"
    image     = "${aws_ecr_repository.openclaw.repository_url}:latest"
    essential = true

    environment = [
      {
        name  = "AGENT_TYPE"
        value = "butler"
      },
      {
        name  = "DB_HOST"
        value = split(":", var.db_endpoint)[0]
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "S3_BUCKET"
        value = var.agent_data_bucket
      }
    ]

    secrets = [
      {
        name      = "DB_PASSWORD"
        valueFrom = "${var.db_secret_arn}:password::"
      },
      {
        name      = "DB_USERNAME"
        valueFrom = "${var.db_secret_arn}:username::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.openclaw_agents.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "butler"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python -c 'import sys; sys.exit(0)'"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name = "${var.project_name}-${var.environment}-butler-template"
  }
}

# ECS Task Definition Template (for Scout agent)
resource "aws_ecs_task_definition" "scout_template" {
  family                   = "${var.project_name}-${var.environment}-scout"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "openclaw-scout"
    image     = "${aws_ecr_repository.openclaw.repository_url}:latest"
    essential = true

    environment = [
      {
        name  = "AGENT_TYPE"
        value = "scout"
      },
      {
        name  = "DB_HOST"
        value = split(":", var.db_endpoint)[0]
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "S3_BUCKET"
        value = var.agent_data_bucket
      }
    ]

    secrets = [
      {
        name      = "DB_PASSWORD"
        valueFrom = "${var.db_secret_arn}:password::"
      },
      {
        name      = "DB_USERNAME"
        valueFrom = "${var.db_secret_arn}:username::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.openclaw_agents.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "scout"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python -c 'import sys; sys.exit(0)'"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name = "${var.project_name}-${var.environment}-scout-template"
  }
}

# ECS Task Definition Template (for Writer/Strategist agent)
resource "aws_ecs_task_definition" "writer_template" {
  family                   = "${var.project_name}-${var.environment}-writer"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "openclaw-writer"
    image     = "${aws_ecr_repository.openclaw.repository_url}:latest"
    essential = true

    environment = [
      {
        name  = "AGENT_TYPE"
        value = "writer"
      },
      {
        name  = "DB_HOST"
        value = split(":", var.db_endpoint)[0]
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "S3_BUCKET"
        value = var.agent_data_bucket
      }
    ]

    secrets = [
      {
        name      = "DB_PASSWORD"
        valueFrom = "${var.db_secret_arn}:password::"
      },
      {
        name      = "DB_USERNAME"
        valueFrom = "${var.db_secret_arn}:username::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.openclaw_agents.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "writer"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python -c 'import sys; sys.exit(0)'"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name = "${var.project_name}-${var.environment}-writer-template"
  }
}

# Data source for current region
data "aws_region" "current" {}

# Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.openclaw.repository_url
}

output "task_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "butler_task_definition_arn" {
  description = "ARN of the Butler task definition"
  value       = aws_ecs_task_definition.butler_template.arn
}

output "scout_task_definition_arn" {
  description = "ARN of the Scout task definition"
  value       = aws_ecs_task_definition.scout_template.arn
}

output "writer_task_definition_arn" {
  description = "ARN of the Writer task definition"
  value       = aws_ecs_task_definition.writer_template.arn
}
