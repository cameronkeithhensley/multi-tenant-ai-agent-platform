# Bastion Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (e.g., production, staging)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where bastion will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for bastion deployment"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID of RDS instance to allow bastion access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for bastion"
  type        = string
  default     = "t3.micro"  # Free tier eligible
}
