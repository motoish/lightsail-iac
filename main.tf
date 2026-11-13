terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "lightsail-iac"
}

resource "aws_lightsail_key_pair" "this" {
  name       = "${var.instance_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_lightsail_instance" "this" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.this.name
}

resource "aws_lightsail_static_ip" "this" {
  name = "${var.instance_name}-ip"
}

resource "aws_lightsail_static_ip_attachment" "this" {
  static_ip_name = aws_lightsail_static_ip.this.name
  instance_name  = aws_lightsail_instance.this.name
}

moved {
  from = aws_lightsail_instance_public_ports.ssh_only
  to   = aws_lightsail_instance_public_ports.this
}

resource "aws_lightsail_instance_public_ports" "this" {
  instance_name = aws_lightsail_instance.this.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }

  port_info {
    protocol  = "udp"
    from_port = var.wireguard_port
    to_port   = var.wireguard_port
    cidrs     = var.wireguard_allowed_cidrs
  }

  port_info {
    protocol  = "tcp"
    from_port = var.proxy_port
    to_port   = var.proxy_port
    cidrs     = var.proxy_allowed_cidrs
  }

  port_info {
    protocol  = "udp"
    from_port = var.proxy_port
    to_port   = var.proxy_port
    cidrs     = var.proxy_allowed_cidrs
  }
}
