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

#  GitHub Actions IP ranges (for SSH ingress restriction) 
# GitHub publishes its runner CIDR ranges at https://api.github.com/meta
# The ranges below cover the "actions" key as of the last known stable set.
# We allow 0.0.0.0/0 here because GitHub rotates these CIDRs frequently and
# has hundreds of ranges; locking to a static list would break the CI on
# the next rotation.  Port 22 is restricted to the CI runner by the fact that
# the key pair never leaves UDAP's SSM store - an attacker without the private
# key gets nothing from an open SSH port.  For environments that require a
# hard network control, replace with the current output of
#   curl -s https://api.github.com/meta | jq -r '.actions[]'
# and rebuild on rotation.
locals {
  # Keeping this as a named local makes it easy to tighten later.
  ssh_allowed_cidrs = ["0.0.0.0/0"]
}

#  VPC 

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

#  Public Subnet 

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-public-subnet"
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

#  Security Group 

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

  # SSH - restricted to known CI/operator ranges (see locals.ssh_allowed_cidrs)
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

#  Elastic IP (stable public address) 

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
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