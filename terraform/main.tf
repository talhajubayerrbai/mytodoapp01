terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

#  Variables 

variable "project_name" {
  description = "Project name used for tagging and naming resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
}

variable "public_key" {
  description = "SSH public key material to install on the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "tododb"
}

variable "db_user" {
  description = "PostgreSQL master username"
  type        = string
  default     = "todouser"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

#  Provider 

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "udap"
    }
  }
}

#  AMI: Latest Canonical Ubuntu 22.04 LTS 

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  ssh_allowed_cidrs = ["0.0.0.0/0"]
}

#  VPC 

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

#  Public Subnet (EC2) 

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

#  Private Subnets (RDS — two AZs required for subnet group) 

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-private-subnet-b"
  }
}

#  Internet Gateway 

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

#  Route Table 

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#  Security Groups 

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name} application server"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "SSH for CI/Ansible provisioning"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.ssh_allowed_cidrs
  }

  # All egress
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL access from the app EC2 instance only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

#  SSH Key Pair 

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-deployer-key"
  public_key = var.public_key

  tags = {
    Name = "${var.project_name}-deployer-key"
  }
}

#  EC2 Instance 

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-app"
    Project = var.project_name
  }
}

#  Elastic IP 

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

#  RDS Subnet Group 

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

#  RDS PostgreSQL Instance 

resource "aws_db_instance" "postgres" {
  identifier              = "${var.project_name}-db"
  engine                  = "postgres"
  engine_version          = "15.7"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  storage_encrypted       = true

  db_name                 = var.db_name
  username                = var.db_user
  password                = var.db_password

  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]

  publicly_accessible     = false
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 7

  tags = {
    Name = "${var.project_name}-db"
  }
}

#  Outputs 

output "instance_public_ip" {
  description = "Static public IP of the application server"
  value       = aws_eip.app.public_ip
}

output "app_url" {
  description = "Public URL of the application"
  value       = "http://${aws_eip.app.public_ip}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_host" {
  description = "RDS PostgreSQL hostname"
  value       = aws_db_instance.postgres.address
}
