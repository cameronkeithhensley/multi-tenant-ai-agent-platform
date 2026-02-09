# Bastion Module - EC2 Jump Box for Database Access
# Deploys a tiny EC2 instance in public subnet for secure RDS access

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.environment}-bastion-"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSH access from anywhere (you can restrict to your IP)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: Restrict to your IP for production
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for bastion (allows Systems Manager access)
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion"
  }
}

# Policy to read database credentials
resource "aws_iam_role_policy" "bastion_secrets" {
  name = "${var.project_name}-${var.environment}-bastion-secrets"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:openclaw-*"
      }
    ]
  })
}

# Attach SSM policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for bastion
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion"
  role = aws_iam_role.bastion.name

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion"
  }
}

# Generate SSH key pair
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-${var.environment}-bastion"
  public_key = tls_private_key.bastion.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion"
  }
}

# Store private key in Secrets Manager
resource "aws_secretsmanager_secret" "bastion_key" {
  name                    = "${var.project_name}-${var.environment}-bastion-ssh-key"
  description             = "SSH private key for bastion host"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-ssh-key"
  }
}

resource "aws_secretsmanager_secret_version" "bastion_key" {
  secret_id     = aws_secretsmanager_secret.bastion_key.id
  secret_string = tls_private_key.bastion.private_key_pem
}

# Bastion EC2 Instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.bastion.key_name
  subnet_id              = var.public_subnet_ids[0]  # First public subnet
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # Enable public IP
  associate_public_ip_address = true

  # User data script to install PostgreSQL client
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y postgresql16
              EOF

  # Storage
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  # Metadata options for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Require IMDSv2
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion"
  }

  lifecycle {
    ignore_changes = [
      ami,  # Don't recreate when new AMI available
    ]
  }
}

# Update RDS security group to allow bastion access
resource "aws_security_group_rule" "rds_from_bastion" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.rds_security_group_id
  source_security_group_id = aws_security_group.bastion.id
  description              = "PostgreSQL from bastion host"
}

# Outputs
output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Instance ID of bastion host"
  value       = aws_instance.bastion.id
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i bastion-key.pem ec2-user@${aws_instance.bastion.public_ip}"
}

output "ssh_key_secret_arn" {
  description = "ARN of secret containing SSH private key"
  value       = aws_secretsmanager_secret.bastion_key.arn
}
