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