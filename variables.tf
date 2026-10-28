variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "nt548-lab01"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "availability_zone" {
  type    = string
  default = "ap-southeast-1a"
}

variable "allowed_ssh_cidr" {
  description = "IP cua ban de SSH vao Public EC2, dang x.x.x.x/32"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr phai la CIDR hop le va khong duoc la 0.0.0.0/0."
  }
}

variable "public_key_path" {
  description = "Duong dan toi file public key (.pub)"
  type        = string
  default     = "~/.ssh/nt548-lab01.pub"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
