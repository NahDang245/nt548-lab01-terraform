resource "aws_security_group" "public" {
  name        = "${var.project_name}-public-ec2-sg"
  description = "Public EC2: SSH from a specific IP only"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-public-ec2-sg" }
}

resource "aws_security_group" "private" {
  name        = "${var.project_name}-private-ec2-sg"
  description = "Private EC2: SSH from Public EC2 SG only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from Public EC2"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  egress {
    description = "Allow all outbound (via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-private-ec2-sg" }
}
