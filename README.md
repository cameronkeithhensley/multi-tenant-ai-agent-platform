# OpenClaw Multi-Tenant AI Agent Platform

A security-hardened, production-ready infrastructure for deploying OpenClaw AI agents at scale on AWS ECS Fargate.

## 🏗️ Architecture Overview

```
GitHub Repository (Source of Truth)
    ↓
GitHub Actions (CI/CD via OIDC)
    ↓
AWS Infrastructure (Terraform-managed)
    ├── VPC (Isolated Network)
    ├── ECS Fargate (Clustered Agents)
    ├── RDS PostgreSQL (Multi-tenant DB)
    ├── S3 (Agent Data Storage)
    └── Secrets Manager (OAuth Tokens)
```

### Multi-Tenant Architecture

- **Shared ECS Cluster**: Cost-efficient, scales to 1000+ customers
- **Task-Level Isolation**: Each customer gets 3 tasks (Butler, Scout, Writer)
- **Row-Level Security**: PostgreSQL enforces tenant isolation at the database level
- **S3 Prefix Isolation**: Bucket policies enforce `/customer-id/` paths
- **IAM Scoping**: Each task role has tenant-specific permissions

## 📋 Prerequisites

1. **AWS Account** with:
   - Administrator access (for initial setup)
   - Budget: ~$50-100/month for dev, ~$300-500/month for production

2. **GitHub Repository**:
   - Fork or create a new repo from this template
   - Set repository secrets (see below)

3. **Local Tools** (for development):
   - Terraform >= 1.6.0
   - AWS CLI >= 2.0
   - Docker >= 20.10

## 🚀 Quick Start Guide

### Step 1: Manual Bootstrap (One-Time Setup)

Before Terraform can run, you need to manually create the S3 bucket and DynamoDB table for state management:

```bash
# Set your AWS account ID and region
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket openclaw-terraform-state \
  --region $AWS_REGION

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket openclaw-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket openclaw-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name openclaw-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION
```

### Step 2: Configure GitHub Repository Secrets

Add these secrets to your GitHub repository (`Settings → Secrets and variables → Actions`):

```
AWS_ACCOUNT_ID: your-aws-account-id
```

That's it! The OIDC integration handles authentication without long-term credentials.

### Step 3: Deploy Infrastructure

```bash
# Clone your repository
git clone https://github.com/yourorg/openclaw-saas.git
cd openclaw-saas

# Initialize Terraform (local testing)
cd terraform
terraform init

# Review the plan
terraform plan

# Apply (or push to main branch to trigger GitHub Actions)
terraform apply
```

### Step 4: Build and Deploy OpenClaw Docker Image

Create a `Dockerfile` in your repository root:

```dockerfile
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw
RUN pip install --no-cache-dir \
    anthropic \
    boto3 \
    psycopg2-binary \
    python-dotenv \
    requests

# Clone OpenClaw (replace with your fork if modified)
WORKDIR /app
RUN git clone https://github.com/OpenClaw/openclaw.git .

# Copy agent configurations
COPY openclaw/ /app/

# Set entrypoint
ENTRYPOINT ["python", "main.py"]
```

Push to GitHub to trigger the build pipeline:

```bash
git add Dockerfile openclaw/
git commit -m "Add OpenClaw Docker image"
git push origin main
```

## 🔐 Security Features

### 1. Zero-Trust Network Architecture
- Private subnets for all compute and data resources
- VPC endpoints for AWS services (no internet egress)
- Security groups with least-privilege rules

### 2. Multi-Tenant Isolation
- **Database**: PostgreSQL Row-Level Security (RLS)
  ```sql
  CREATE POLICY tenant_isolation ON leads
    USING (tenant_id = current_setting('app.tenant_id')::uuid);
  ```
- **Storage**: S3 bucket policies with prefix restrictions
- **Compute**: Separate ECS tasks with scoped IAM roles

### 3. Secrets Management
- OAuth tokens stored in AWS Secrets Manager
- Automatic secret rotation (optional)
- Secrets injected at runtime (never in code)

### 4. Audit & Compliance
- CloudWatch Logs for all agent activity
- X-Ray tracing for cross-service calls
- Resource tagging for cost attribution per tenant

## 📊 Cost Breakdown

### Development Environment
| Resource | Monthly Cost |
|----------|--------------|
| ECS Fargate (3 tasks @ 0.5 vCPU) | $40 |
| RDS PostgreSQL (db.t4g.micro) | $15 |
| NAT Gateway (1 AZ) | $32 |
| S3 Storage (10 GB) | $3 |
| Data Transfer | $10 |
| **Total** | **~$100/month** |

### Production Environment (10 customers)
| Resource | Monthly Cost |
|----------|--------------|
| ECS Fargate (30 tasks) | $400 |
| RDS PostgreSQL (db.t4g.medium) | $60 |
| NAT Gateway (2 AZ) | $64 |
| S3 Storage (100 GB) | $25 |
| Bedrock API (Claude Sonnet) | $1,500 |
| Data Transfer | $50 |
| **Total** | **~$2,100/month** |

**Revenue**: $5,000/month (10 customers @ $500/month)  
**Profit Margin**: 58%

### Cost Optimization Tips
1. Use **Bedrock on-demand** (no upfront cost) vs. provisioned capacity
2. Enable **Spot instances** for non-critical tasks (70% discount)
3. Use **S3 Intelligent-Tiering** for automatic cost reduction
4. Implement **auto-scaling** to scale down during off-hours

## 🎯 Adding Your First Customer

### 1. Create Database Schema

```sql
-- Connect to RDS
psql -h <rds-endpoint> -U openclaw_admin -d openclaw

-- Create customer schema
CREATE SCHEMA customer_abc;

-- Create tables with tenant isolation
CREATE TABLE customer_abc.leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL DEFAULT 'customer-abc-uuid'::uuid,
  name TEXT,
  email TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row-Level Security
ALTER TABLE customer_abc.leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON customer_abc.leads
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

### 2. Store OAuth Tokens

```bash
# Create secret for customer's Gmail OAuth token
aws secretsmanager create-secret \
  --name /openclaw/customer-abc/gmail-oauth \
  --description "Gmail OAuth token for customer ABC" \
  --secret-string '{
    "access_token": "ya29.a0...",
    "refresh_token": "1//0e...",
    "token_uri": "https://oauth2.googleapis.com/token",
    "client_id": "your-client-id.apps.googleusercontent.com",
    "client_secret": "your-client-secret",
    "scopes": ["https://www.googleapis.com/auth/gmail.readonly"]
  }'
```

### 3. Deploy Agent Tasks

```bash
# Run Butler task for customer ABC
aws ecs run-task \
  --cluster openclaw-production \
  --task-definition openclaw-production-butler \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-xxx,subnet-yyy],
    securityGroups=[sg-xxx],
    assignPublicIp=DISABLED
  }" \
  --overrides '{
    "containerOverrides": [{
      "name": "openclaw-butler",
      "environment": [
        {"name": "TENANT_ID", "value": "customer-abc"},
        {"name": "CUSTOMER_EMAIL", "value": "user@company.com"}
      ]
    }]
  }' \
  --tags key=TenantID,value=customer-abc
```

Repeat for Scout and Writer agents.

## 🛠️ Development Workflow

### Local Development

```bash
# Run OpenClaw locally with local PostgreSQL
docker-compose up -d postgres

# Set environment variables
export DB_HOST=localhost
export DB_NAME=openclaw
export TENANT_ID=test-customer
export AWS_REGION=us-east-1

# Run agent
python openclaw/main.py
```

### Testing Changes

```bash
# Create a feature branch
git checkout -b feature/new-agent-capability

# Make changes to openclaw/ directory

# Test locally
docker build -t openclaw-test .
docker run --env-file .env openclaw-test

# Push to GitHub (triggers CI/CD)
git push origin feature/new-agent-capability
```

### Terraform Changes

```bash
# Make infrastructure changes
cd terraform/
terraform plan

# Create PR to review changes
git add terraform/
git commit -m "Add new VPC endpoint"
git push origin feature/infrastructure-update
```

GitHub Actions will automatically run `terraform plan` and comment on the PR.

## 📈 Scaling to 100+ Customers

### Database Scaling

1. **Vertical Scaling**: Upgrade RDS instance class
   ```hcl
   db_instance_class = "db.r6g.xlarge"  # 4 vCPU, 32 GB RAM
   ```

2. **Read Replicas**: Add for read-heavy workloads
   ```hcl
   resource "aws_db_instance" "replica" {
     replicate_source_db = aws_db_instance.main.id
     instance_class      = "db.t4g.medium"
   }
   ```

3. **Connection Pooling**: Use RDS Proxy
   ```hcl
   resource "aws_db_proxy" "main" {
     name                   = "openclaw-proxy"
     engine_family          = "POSTGRESQL"
     auth { ... }
   }
   ```

### Compute Scaling

1. **Auto-Scaling**: Based on CPU/memory utilization
   ```hcl
   resource "aws_appautoscaling_target" "ecs_target" {
     max_capacity       = 100
     min_capacity       = 10
     resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.butler.name}"
     scalable_dimension = "ecs:service:DesiredCount"
     service_namespace  = "ecs"
   }
   ```

2. **Spot Instances**: 70% cost savings for non-critical tasks
   ```hcl
   capacity_provider_strategy {
     capacity_provider = "FARGATE_SPOT"
     weight            = 1
   }
   ```

## 🚨 Troubleshooting

### Common Issues

1. **Terraform State Lock**
   ```bash
   # Force unlock (use cautiously)
   terraform force-unlock <lock-id>
   ```

2. **ECS Task Won't Start**
   ```bash
   # Check CloudWatch Logs
   aws logs tail /aws/ecs/openclaw-production/agents --follow
   
   # Check task definition
   aws ecs describe-tasks --cluster openclaw-production --tasks <task-id>
   ```

3. **Database Connection Issues**
   ```bash
   # Test connectivity from ECS task
   aws ecs execute-command \
     --cluster openclaw-production \
     --task <task-id> \
     --container openclaw-butler \
     --interactive \
     --command "pg_isready -h $DB_HOST"
   ```

4. **OAuth Token Expired**
   ```bash
   # Refresh token (implement OAuth refresh flow in agent)
   # Or manually update secret:
   aws secretsmanager update-secret \
     --secret-id /openclaw/customer-abc/gmail-oauth \
     --secret-string '{"access_token": "new-token"}'
   ```

## 📚 Additional Resources

- [OpenClaw Documentation](https://github.com/OpenClaw/openclaw)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [OAuth 2.0 Guide](https://oauth.net/2/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙋 Support

- GitHub Issues: [https://github.com/yourorg/openclaw-saas/issues](https://github.com/yourorg/openclaw-saas/issues)
- Email: support@yourcompany.com
- Slack: [Join our community](https://yourcompany.slack.com)
