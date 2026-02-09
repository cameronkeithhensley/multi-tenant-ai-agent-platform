# OpenClaw Multi-Tenant SaaS Infrastructure
# Provider: AWS (us-east-1)
# Architecture: ECS Fargate + RDS PostgreSQL + S3

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration - store state in S3
  backend "s3" {
    bucket         = "openclaw-terraform-state-207128437758"  # Create this manually first
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "openclaw-terraform-locks"  # Create this manually first
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "OpenClaw"
      Environment = var.environment
      ManagedBy   = "Terraform"
      GitRepo     = "github.com/yourorg/openclaw-infrastructure"
    }
  }
}

# Local variables
locals {
  project_name = "openclaw"
  common_tags = {
    Project     = local.project_name
    Environment = var.environment
  }
}

# Import modules
module "networking" {
  source = "./modules/networking"
  
  project_name        = local.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
}

module "database" {
  source = "./modules/database"
  
  project_name       = local.project_name
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  db_instance_class  = var.db_instance_class
  db_name            = var.db_name
  db_username        = var.db_username
}

# Bastion Host for Database Access
module "bastion" {
  source = "./modules/bastion"

  project_name           = "openclaw"
  environment            = "production"
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  rds_security_group_id  = module.database.db_security_group_id
  instance_type          = "t3.micro"
}

module "storage" {
  source = "./modules/storage"
  
  project_name = local.project_name
  environment  = var.environment
}

module "compute" {
  source = "./modules/compute"
  
  project_name       = local.project_name
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  db_endpoint        = module.database.db_endpoint
  db_secret_arn      = module.database.db_secret_arn
  agent_data_bucket  = module.storage.agent_data_bucket_name
}

module "security" {
  source = "./modules/security"
  
  project_name = local.project_name
  environment  = var.environment
}

# Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.compute.ecs_cluster_name
}

output "database_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.database.db_endpoint
}

output "agent_data_bucket" {
  description = "S3 bucket for agent data storage"
  value       = module.storage.agent_data_bucket_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for OpenClaw images"
  value       = module.compute.ecr_repository_url
}

# Bastion outputs
output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = module.bastion.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect"
  value       = module.bastion.bastion_ssh_command
}
