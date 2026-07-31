# Account-level values for the two shared units (ecr, github-oidc).

repository_name = "devops-task-app"

github_org  = "yoavmanoim-prog"
github_repo = "devops-task-app"

# false because THIS account (302954730632) already has a GitHub OIDC provider,
# created 2026-05-31 by an earlier project whose `pdm-github-actions` role still
# trusts it. It's account-global, so we adopt it read-only rather than creating
# a second one (impossible) or importing it (which would let `destroy` here
# break that project). Leave this at its `true` default in a fresh account.
create_oidc_provider = false

tags = {
  Project = "devops-task"
}
