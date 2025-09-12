# Security Group for FTP Server
resource "aws_security_group" "ftp_server" {
  name_prefix = "ftp-server-"
  vpc_id      = var.vpc_id
  description = "Security group for FTP server"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # FTP control port
  ingress {
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Passive FTP data ports
  ingress {
    from_port   = 50000
    to_port     = 50050
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ftp-server-sg"
    Environment = "production"
  }
}

# IAM Role for EC2 instance
resource "aws_iam_role" "ftp_server_role" {
  name = "ftp-server-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ftp-server-ec2-role"
    Environment = "production"
  }
}

# IAM Policy for S3 access
resource "aws_iam_policy" "ftp_server_s3_policy" {
  name        = "ftp-server-s3-policy"
  description = "Policy for FTP server to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ftp_server_s3_policy" {
  role       = aws_iam_role.ftp_server_role.name
  policy_arn = aws_iam_policy.ftp_server_s3_policy.arn
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ftp_server_profile" {
  name = "ftp-server-instance-profile"
  role = aws_iam_role.ftp_server_role.name
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    ftp_username          = var.ftp_username
    ftp_password          = var.ftp_password
    s3_bucket_name        = var.s3_bucket_name
    aws_region            = var.aws_region
    aws_access_key_id     = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
  }))
}

resource "aws_instance" "ftp_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ftp_server.id]
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.ftp_server_profile.name

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 10
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "ftp-server"
    Environment = "production"
  }

  lifecycle {
    create_before_destroy = true
  }
}
