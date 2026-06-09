variable "domain_name" {
  description = "Domen"
  default     = "wolflife.net"
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "subdomain" {
  description = "Subdomain"
  default     = "task324"
}

variable "my_ip" {
  description = "My public IP for SSH "
  default     = "89.149.93.193/32"
}

variable "ec2_public_key" {
  description = "Public key"
  type        = string
}
variable "redis_password" {
  description = "Password for Redis AUTH token"
  type        = string
  sensitive   = true
}
