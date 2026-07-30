variable "github_org" {
  description = "GitHub org/user that owns the app repo, e.g. \"yoavmanoim-prog\""
  type        = string
}

variable "github_repo" {
  description = "App repo name this role trusts, e.g. \"devops-task-app\". The role is scoped to this one repo, not to a specific branch/ref, because CI runs the same ECR-push step from three long-lived branches (dev/staging/prod) - narrowing further to per-branch roles would add three roles for no real isolation gain, since all three only ever push images, never touch prod infra directly."
  type        = string
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
