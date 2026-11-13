output "public_ip" {
  description = "Static IP address attached to the Lightsail instance"
  value       = aws_lightsail_static_ip.this.ip_address
}
