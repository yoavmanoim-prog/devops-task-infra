variable "github_org" {
  description = "GitHub org/user that owns the app repo, e.g. \"yoavmanoim-prog\""
  type        = string
}

variable "github_repo" {
  description = "App repo name this role trusts, e.g. \"devops-task-app\". Scoped to this one repo and only the branches in var.github_branches, not the whole repo (any ref/event) - narrowing further to per-branch roles would add three roles for no real isolation gain, since all three only ever push images, never touch prod infra directly."
  type        = string
}

variable "github_branches" {
  description = "Long-lived branches in github_repo allowed to assume this role - a security-review pass caught that the trust policy previously used a bare `repo:org/repo:*` wildcard, which also matches pull_request events, tags, and arbitrary branches, not just these three. Update this if the app repo's branch names ever change (e.g. it already changed once: prod -> main)."
  type        = list(string)
  default     = ["dev", "staging", "main"]
}

variable "create_oidc_provider" {
  description = "Whether to CREATE the account-global GitHub OIDC provider, or adopt an existing one read-only. Default true keeps this module self-contained in a fresh account. Set false when another project in the same AWS account already created it - creating it twice fails with EntityAlreadyExists, and importing it here would let `destroy` delete a provider that project still depends on. See infra/README.md \"Known limitations\" - this is a shared-account workaround, not real isolation."
  type        = bool
  default     = true
}

variable "role_name" {
  type    = string
  default = "github-actions-ecr-push"
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs this role may push images to. Kept as a list (rather than a single ARN) so one CI role can be reused if a second image/repo is added later without a module change."
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
