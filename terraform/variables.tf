# Terraform Variables for OpenClaw Infrastructure

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"  # ~$15/month
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "openclaw"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "openclaw_admin"
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS tasks (256 = 0.25 vCPU)"
  type        = number
  default     = 512  # 0.5 vCPU
}

variable "ecs_task_memory" {
  description = "Memory for ECS tasks in MB"
  type        = number
  default     = 1024  # 1 GB
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnets (costs ~$32/month)"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo'"
  type        = string
  default     = "cameronkeithhensley/openclaw-saas"
}

variable "bedrock_model_id" {
  description = "AWS Bedrock model ID for Claude"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}
