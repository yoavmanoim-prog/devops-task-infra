# Resolves to whichever of the two paths is active (created here, or adopted
# read-only from an existing account-global provider) - see main.tf.
output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "role_arn" {
  value = aws_iam_role.github_actions.arn
}
