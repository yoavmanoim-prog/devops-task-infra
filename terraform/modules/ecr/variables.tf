variable "repository_name" {
  description = "ECR repository name, e.g. \"devops-task-app\""
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE so a tag (sha-<shortsha> or vX.Y.Z) can never be silently repointed at a different image once pushed - matches the \"no floating tags\" discipline used across this project."
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  type    = bool
  default = true
}

variable "untagged_image_expiry_days" {
  description = "Untagged images (superseded manifests from re-pushes) are expired after this many days; tagged images are never touched by this rule."
  type        = number
  default     = 7
}

variable "tagged_image_keep_count" {
  description = "How many most-recent sha-* tagged images to retain; older ones are expired. Keeps the registry from growing unbounded across a long-running demo/interview review period."
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
