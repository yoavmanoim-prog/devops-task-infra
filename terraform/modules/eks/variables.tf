variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  description = "Kubernetes version. Pin explicitly - never leave this to drift to whatever EKS defaults to."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnet IDs the control plane ENIs and worker nodes are placed in"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Whether the API server endpoint is reachable from outside the VPC. true for this demo so candidates/reviewers can kubectl in without a bastion/VPN; document restricting this via cluster_endpoint_public_access_cidrs in a real environment."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "enable_cluster_encryption" {
  description = "Envelope-encrypt Kubernetes secrets at rest with a customer-managed KMS key. Recommended on for prod, optional for dev to keep the demo cheap/fast."
  type        = bool
  default     = false
}

variable "cluster_log_types" {
  description = "Control plane log types shipped to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group configurations. Deliberately left generic so dev/prod can each pass their own sizing via Terragrunt inputs."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "authentication_mode" {
  description = "EKS cluster access management mode. API_AND_CONFIG_MAP keeps the legacy aws-auth ConfigMap working while allowing the newer Access Entry API - the safer default while migrating an existing org off aws-auth."
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "admin_role_arns" {
  description = "IAM role ARNs (e.g. CI/CD role, break-glass SSO role) granted cluster-admin access entries in addition to the Terraform caller."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
