variable "name" {
  description = "Name prefix for the VPC and all derived resources"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across - also determines how many private/public subnet CIDRs get carved out of var.cidr (one pair per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway (cheap, non-HA - fine for dev). Set false for prod (one NAT per AZ)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name that will consume this VPC - used for the required kubernetes.io/cluster/<name> subnet tags"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
