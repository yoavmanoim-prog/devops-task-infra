# thumbprint_list is a required field on the resource, but AWS has validated
# GitHub's OIDC tokens against its own trusted root CA bundle since 2023 and
# ignores the value supplied here - fetching it live via `tls_certificate`
# still satisfies the schema without hardcoding a fingerprint that would
# silently go stale on GitHub's next cert rotation.
data "tls_certificate" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# The GitHub OIDC identity provider is ACCOUNT-GLOBAL - exactly one can exist
# per URL per AWS account - so this module must not assume it owns one.
# Creating it unconditionally fails with EntityAlreadyExists in any account
# where something else got there first, which is what happened here: an
# earlier project in this account created it on 2026-05-31 and one of its
# roles still trusts it.
#
# Importing it into this project's state would have "worked", but would then
# let `terragrunt destroy` delete a provider another project depends on. So
# instead: create it when this project is genuinely the first one in the
# account (the default, keeping the module self-contained), or adopt the
# existing one read-only and leave ownership where it already is.
#
# This is a workaround for sharing one AWS account across projects, not a
# substitute for real isolation - see infra/README.md "Known limitations".
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : data.aws_iam_openid_connect_provider.github_actions[0].arn

  # GitHub can issue the `sub` claim in two shapes, and which one you get is an
  # account-level setting ("immutable numeric IDs"):
  #
  #   plain : repo:ORG/REPO:ref:refs/heads/dev
  #   ids   : repo:ORG@<owner_id>/REPO@<repo_id>:ref:refs/heads/dev
  #
  # This account has the ID form enabled, which is why the first real CI run
  # failed with "Not authorized to perform sts:AssumeRoleWithWebIdentity"
  # despite a trust policy that looked correct - it only listed the plain form.
  #
  # Both forms are listed EXACTLY, deliberately without wildcards. Something
  # like `repo:ORG*/REPO*` would also match an org an attacker can register
  # (ORG-evil), which is a real privilege-escalation path in OIDC trust
  # policies. The ID form is the stronger of the two: it pins to this exact
  # account and repository, so a repo that is renamed or deleted and recreated
  # under the same name gets a new ID and is denied.
  subject_claims = flatten([
    for branch in var.github_branches : compact([
      "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${branch}",
      var.github_owner_id != "" && var.github_repo_id != "" ?
      "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/${branch}" : "",
    ])
  ])
}

# Trust policy scopes AssumeRoleWithWebIdentity to tokens whose `sub` claim
# names this exact org/repo AND one of var.github_branches - any other
# GitHub repo's workflow is rejected at the STS layer before IAM policy
# evaluation even runs, and so is anything in this repo that isn't a push
# to one of those branches (a pull_request run, a tag push, an arbitrary
# feature branch) - a bare `repo:org/repo:*` wildcard would satisfy all of
# those too, which a security-review pass flagged as broader than intended.
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike: every entry in local.subject_claims is a
    # complete literal, so there is nothing to pattern-match and no way for a
    # stray wildcard to widen this later.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subject_claims
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# ecr:GetAuthorizationToken is account-scoped by the ECR API itself (it
# doesn't accept a repository resource) so it's the one action left on "*";
# every other action is pinned to the specific repository ARN(s) this role
# is meant to push to, not "all repos in the account".
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      # Required by the staging/prod promotion workflows, which call
      # `aws ecr describe-images` to prove the tag being promoted actually
      # exists before writing it into the gitops repo. Omitting it failed the
      # first real dev->staging promotion with AccessDeniedException. Unlike
      # GetAuthorizationToken this IS resource-scoped, so it stays pinned to
      # the repository ARNs rather than "*".
      "ecr:DescribeImages",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
