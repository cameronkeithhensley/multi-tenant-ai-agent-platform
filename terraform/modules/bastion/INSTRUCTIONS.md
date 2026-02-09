# Adding Bastion Host to Your Infrastructure

## Step 1: Copy Module Files

```bash
cd ~/Documents/openclaw-saas/terraform

# Create bastion module directory
mkdir -p modules/bastion

# Copy the files I created (download them first from this conversation)
# Place main.tf and variables.tf in modules/bastion/
```

## Step 2: Update terraform/main.tf

Add this module block AFTER the database module (around line 50):

```hcl
# Bastion Host for Database Access
module "bastion" {
  source = "./modules/bastion"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  rds_security_group_id  = module.database.db_security_group_id
  instance_type          = "t3.micro"  # Free tier eligible
}
```

## Step 3: Add Outputs to terraform/main.tf

Add these outputs at the bottom of main.tf:

```hcl
# Bastion outputs
output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = module.bastion.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = module.bastion.bastion_ssh_command
}
```

## Step 4: Deploy

```bash
# Initialize new module
terraform init

# Review changes
terraform plan

# Apply (creates bastion host - takes ~2 minutes)
terraform apply
```

## Step 5: Get SSH Key

After deployment, retrieve the SSH private key:

```bash
# Get the SSH private key from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id openclaw-production-bastion-ssh-key \
  --query SecretString \
  --output text > ~/bastion-key.pem

# Set correct permissions
chmod 400 ~/bastion-key.pem
```

## Step 6: Connect to Bastion

```bash
# Get bastion IP from Terraform outputs
terraform output bastion_public_ip

# SSH to bastion
ssh -i ~/bastion-key.pem ec2-user@<BASTION_IP>
```

## Step 7: Connect to RDS from Bastion

Once connected to bastion:

```bash
# Get DB credentials
aws secretsmanager get-secret-value \
  --secret-id openclaw-production-db-credentials \
  --query SecretString \
  --output text

# Connect to RDS (PostgreSQL client already installed on bastion)
psql -h openclaw-production-postgres.ccjsg64qgxa7.us-east-1.rds.amazonaws.com \
     -p 5432 \
     -U openclaw_admin \
     -d openclaw
```

## Monthly Cost

**Bastion Host:** ~$7.50/month (t3.micro, 730 hours)

**To Save Money:**
- Stop the instance when not using it: `$0/month`
- Start only when you need database access
- Or use AWS Systems Manager Session Manager instead (free)

---

## Alternative: Use Systems Manager (No SSH Key Needed)

If you want to avoid managing SSH keys:

```bash
# Connect via Systems Manager
aws ssm start-session --target <BASTION_INSTANCE_ID>

# Then run psql commands
```

This is more secure and doesn't require opening port 22.
