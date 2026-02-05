variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, production)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (for future ALB)"
  type        = list(string)
}

variable "db_endpoint" {
  description = "RDS database endpoint"
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the database credentials secret"
  type        = string
}

variable "agent_data_bucket" {
  description = "Name of the S3 bucket for agent data"
  type        = string
}
