# ECS Task Definition for Butler Agent
resource "aws_ecs_task_definition" "butler" {
  family                   = "${var.project_name}-${var.environment}-butler"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 512 MB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "butler"
      image     = "${var.ecr_repository_url}:latest"
      essential = true

      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "CLAUDE_MODEL_ID"
          value = "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
        },
        {
          name  = "TENANT_ID"
          value = "customer-001"
        },
        {
          name  = "DB_HOST"
          value = var.db_host
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_username
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = var.db_password_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-${var.environment}/butler"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "butler"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "python butler.py --health-check || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

# CloudWatch Log Group for Butler
resource "aws_cloudwatch_log_group" "butler" {
  name              = "/ecs/${var.project_name}-${var.environment}/butler"
  retention_in_days = 7  # Keep logs for 7 days

  tags = {
    Name        = "${var.project_name}-${var.environment}-butler-logs"
    Environment = var.environment
  }
}

# ECS Service for Butler
resource "aws_ecs_service" "butler" {
  name            = "${var.project_name}-${var.environment}-butler"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.butler.arn
  desired_count   = 1  # Run 1 instance
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Enable service discovery (optional, for later)
  # service_registries {
  #   registry_arn = aws_service_discovery_service.butler.arn
  # }

  tags = {
    Name        = "${var.project_name}-${var.environment}-butler-service"
    Environment = var.environment
  }
}
