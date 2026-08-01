# Account-level values for the two shared units (ecr, github-oidc).

repository_name = "devops-task-app"

github_org  = "yoavmanoim-prog"
github_repo = "devops-task-app"

# This account has OIDC "immutable numeric IDs" enabled, so GitHub issues the
# sub claim as repo:ORG@<owner_id>/REPO@<repo_id>:ref:... rather than the plain
# repo:ORG/REPO:ref:.... Without these the trust policy matches only the plain
# form and every CI run fails AssumeRoleWithWebIdentity - which is exactly how
# the first real pipeline run failed.
#
# Not secrets: both are public and readable unauthenticated. Pinning them is
# what makes the policy strict - a repo deleted and recreated under the same
# name gets a new ID and is correctly denied.
#   gh api /users/yoavmanoim-prog --jq .id
#   gh api /repos/yoavmanoim-prog/devops-task-app --jq .id
github_owner_id = "251859432"
github_repo_id  = "1317589127"

# false because THIS account (302954730632) already has a GitHub OIDC provider,
# created 2026-05-31 by an earlier project whose `pdm-github-actions` role still
# trusts it. It's account-global, so we adopt it read-only rather than creating
# a second one (impossible) or importing it (which would let `destroy` here
# break that project). Leave this at its `true` default in a fresh account.
create_oidc_provider = false

tags = {
  Project = "devops-task"
}
