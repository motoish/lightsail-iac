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
  default     = "~/.ssh/id_ed25519.pub"
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