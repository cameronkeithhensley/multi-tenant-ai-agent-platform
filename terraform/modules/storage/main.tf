# Storage Module - S3 Buckets for Multi-Tenant Agent Data
# Enforces tenant isolation via bucket policies

# S3 Bucket for Agent Data (shared, tenant-isolated via prefixes)
resource "aws_s3_bucket" "agent_data" {
  bucket = "${var.project_name}-${var.environment}-agent-data"

  tags = {
    Name = "${var.project_name}-${var.environment}-agent-data"
  }
}

# Enable versioning for data protection
resource "aws_s3_bucket_versioning" "agent_data" {
  bucket = aws_s3_bucket.agent_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "agent_data" {
  bucket = aws_s3_bucket.agent_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "agent_data" {
  bucket = aws_s3_bucket.agent_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy to manage costs
resource "aws_s3_bucket_lifecycle_configuration" "agent_data" {
  bucket = aws_s3_bucket.agent_data.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    # Move to Intelligent-Tiering after 30 days
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    # Move to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 365 days (adjust based on retention requirements)
    expiration {
      days = 365
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Bucket policy for tenant isolation
# This ensures agents can only access their own tenant prefix
resource "aws_s3_bucket_policy" "agent_data" {
  bucket = aws_s3_bucket.agent_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceTenantIsolation"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.agent_data.arn}/*",
          aws_s3_bucket.agent_data.arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = ["$${aws:userid}/*"]
          }
        }
      }
    ]
  })
}

# S3 Bucket for Terraform State (if not created manually)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state"

  tags = {
    Name = "${var.project_name}-terraform-state"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for Terraform state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-terraform-locks"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# S3 Bucket for CloudWatch Logs (long-term archival)
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-${var.environment}-logs"

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-logs"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 730  # 2 years retention
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Outputs
output "agent_data_bucket_name" {
  description = "Name of the agent data S3 bucket"
  value       = aws_s3_bucket.agent_data.id
}

output "agent_data_bucket_arn" {
  description = "ARN of the agent data S3 bucket"
  value       = aws_s3_bucket.agent_data.arn
}

output "logs_bucket_name" {
  description = "Name of the logs S3 bucket"
  value       = aws_s3_bucket.logs.id
}

output "terraform_state_bucket_name" {
  description = "Name of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_locks_table_name" {
  description = "Name of the Terraform locks DynamoDB table"
  value       = aws_dynamodb_table.terraform_locks.id
}
