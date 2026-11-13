variable "instance_name" {
  description = "Lightsail instance name"
  type        = string
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID"
  type        = string
}

variable "bundle_id" {
  description = "Lightsail bundle ID"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = "ap-northeast-1a"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key registered as the instance key pair"
  type        = string
  default     = "~/.ssh/lightsail-iac_dev.pub"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to SSH"
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ssh_allowed_cidrs must contain at least one valid CIDR block."
  }

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "ssh_allowed_cidrs must not open SSH to the whole internet (0.0.0.0/0)."
  }
}

variable "wireguard_port" {
  description = "UDP port used by WireGuard"
  type        = number
  default     = 51820
}

variable "wireguard_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to WireGuard"
  type        = list(string)

  validation {
    condition     = length(var.wireguard_allowed_cidrs) > 0 && alltrue([for c in var.wireguard_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "wireguard_allowed_cidrs must contain at least one valid CIDR block."
  }

  validation {
    condition     = !contains(var.wireguard_allowed_cidrs, "0.0.0.0/0")
    error_message = "wireguard_allowed_cidrs must not open WireGuard to the whole internet (0.0.0.0/0)."
  }
}

variable "proxy_port" {
  description = "TCP/UDP port used by the sing-box proxy inbound"
  type        = number
  default     = 8388
}

variable "proxy_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to the sing-box proxy"
  type        = list(string)

  validation {
    condition     = length(var.proxy_allowed_cidrs) > 0 && alltrue([for c in var.proxy_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "proxy_allowed_cidrs must contain at least one valid CIDR block."
  }

  validation {
    condition     = !contains(var.proxy_allowed_cidrs, "0.0.0.0/0")
    error_message = "proxy_allowed_cidrs must not open the proxy to the whole internet (0.0.0.0/0)."
  }
}