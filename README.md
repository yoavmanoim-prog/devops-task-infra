# devops-task-infra

Terraform + Terragrunt IaC for a DevOps Engineer take-home assessment. Provisions two AWS EKS
clusters and everything they need (networking, ArgoCD, ingress, secrets, monitoring), then hands
off to GitOps for everything else.

Part of a 3-repo submission:

- **infra** (this repo) - Terraform modules + Terragrunt live config
- [devops-task-gitops](https://github.com/yoavmanoim-prog/devops-task-gitops) - Helm chart + ArgoCD Application/AppProject manifests
- [devops-task-app](https://github.com/yoavmanoim-prog/devops-task-app) - FastAPI sample app + CI/CD

## Architecture

Two EKS clusters, not three: the **dev** cluster hosts both the `dev` and `staging` namespaces
(isolated by namespace + AppProject + quota/network-policy, not by a separate control plane); the
**prod** cluster hosts `production` alone. See [`docs/architecture-diagram.md`](docs/architecture-diagram.md)
for the full picture.

**Ownership boundary**: Terraform provisions the cluster, its controllers (ALB Ingress Controller,
External Secrets Operator, monitoring), installs ArgoCD, and creates exactly one bootstrap
`Application` per cluster pointing at that cluster's folder in the `gitops` repo. Everything past
that point - namespaces, quotas, network policies, the actual workload - is reconciled by ArgoCD
from `gitops`, not re-applied by Terraform.

### Terraform modules (`terraform/modules/`)

| Module | Scope | What it does |
|---|---|---|
| `vpc` | per-env | VPC + subnets, CIDRs derived from a single base CIDR via `cidrsubnet()`, EKS-required subnet tags, flow logs |
| `eks` | per-env | The EKS cluster itself, managed node groups, IRSA, Access Entry API |
| `alb-controller` | per-env | AWS Load Balancer Controller, IRSA-scoped |
| `external-secrets` | per-env | External Secrets Operator + one `ClusterSecretStore` per cluster, IRSA-scoped to that env's own Secrets Manager paths |
| `argocd` | per-env | ArgoCD via Helm, GitHub OAuth SSO (Dex), RBAC, the one bootstrap `Application` |
| `monitoring` | per-env | kube-prometheus-stack (Prometheus/Alertmanager/Grafana) |
| `ecr` | shared | One ECR repo for the app image - `IMMUTABLE` tags, lifecycle policy |
| `github-oidc` | shared | GitHub Actions OIDC provider + a role scoped to the `app` repo, for keyless ECR push |

### Terragrunt live config (`terragrunt/`)

14 units total: the 6 per-env modules above × 2 envs (`dev`, `prod`), plus the 2 shared modules
applied once. `terragrunt/root.hcl` generates the S3 backend + AWS provider for every unit; the
four units that install workloads onto a cluster (`argocd`, `alb-controller`, `external-secrets`,
`monitoring`) each generate their own `kubernetes`/`helm` provider via `aws_eks_cluster_auth`,
scoped by their own `dependency "eks"` block. Env-specific values come from one flat
`terragrunt/vars/<env>.tfvars` file per environment, passed to every unit via
`extra_arguments { optional_var_files = [...] }` - every unit's `terraform.source` points at the
same shared module.

## Prerequisites

- An AWS account with credentials configured (`aws sts get-caller-identity` should succeed)
- Terraform >= 1.9 (developed against 1.15.5)
- Terragrunt (developed against 1.1.2 - this repo uses its `hcl format`/`hcl validate`/`run --all` subcommands, not the older `hclfmt`/`plan-all` names)
- AWS CLI (2.31.8), kubectl (1.34.1), Helm (4.2.0), Docker (29.1.3)

## Setup & run

### 1. One-time state backend bootstrap

Terraform/Terragrunt can't create the backend they're about to store their own state in. Create
the S3 bucket once, by hand, before anything else:

```sh
aws s3api create-bucket --bucket devops-task-tfstate-302954730632 --region us-east-1
aws s3api put-bucket-versioning --bucket devops-task-tfstate-302954730632 \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket devops-task-tfstate-302954730632 \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

No DynamoDB table needed - state locking uses the S3 backend's own native lockfile
(`use_lockfile = true`, Terraform 1.10+), not a separate lock table.

### 2. Apply, in dependency order

Shared units first, then each environment's `vpc → eks → {argocd, alb-controller, external-secrets, monitoring}`:

```sh
cd terragrunt/shared/modules/ecr && terragrunt apply
cd ../github-oidc && terragrunt apply

cd ../../../dev/modules/vpc && terragrunt apply
cd ../eks && terragrunt apply
cd ../argocd && terragrunt apply    # see step 3 below first
cd ../alb-controller && terragrunt apply
cd ../external-secrets && terragrunt apply
cd ../monitoring && terragrunt apply

# repeat the same 6, from terragrunt/prod/modules/, for the prod cluster
```

Or equivalently, from `terragrunt/`: `terragrunt run --all apply` - the `dependency` blocks in
each unit's `terragrunt.hcl` already encode this same ordering, so it builds the same DAG
automatically rather than needing the manual per-unit sequence above.

### 3. Before applying `argocd`: GitHub OAuth App + secrets

ArgoCD's SSO needs a GitHub OAuth App, and it has to exist before you know the callback URL
you'll register... in practice: apply everything else first, note the ArgoCD NLB hostname once
it's up, create one GitHub OAuth App (reused for both clusters - just register both callback
URLs on it), then export before applying (or re-applying) either `argocd` unit:

```sh
export TF_VAR_github_oauth_client_id="..."
export TF_VAR_github_oauth_client_secret="..."
```

These are intentionally never written to any `.tfvars` file - this is a public repo.

### 4. After apply: wire up the `app` repo's CI

```sh
terragrunt output -raw role_arn   # from terragrunt/shared/modules/github-oidc
```

Set that value as the `AWS_OIDC_ROLE_ARN` **variable** (not secret - ARNs aren't sensitive) on
`devops-task-app`. Also add a fine-grained PAT scoped to `devops-task-gitops` (Contents:
read/write) as the `GITOPS_REPO_TOKEN` **secret** on the same repo - without both, `app`'s CI
can authenticate to AWS but can't push the resulting image tag into `gitops`.

## Assumptions & design decisions

- **2 clusters, not 3.** The spec's literal architecture; staging is isolated by namespace/quota/
  network-policy on the dev cluster rather than a separate control plane.
- **Kubernetes 1.34** on both clusters (in standard support through Oct 2026 as of this writing).
- **No floating tags, anywhere.** ECR images are `sha-<shortsha>` (+ `vX.Y.Z` on version tags),
  never `:latest`; the `ecr` module's repository is `IMMUTABLE`; every Terraform module and Helm
  chart version in this repo is pinned to an exact version, never a range.
- **One shared GitHub OAuth App** reused across both ArgoCD instances (different callback URIs
  registered on the one App) rather than one per cluster.
- **Feature-branch-per-step git workflow** - every module/component landed as its own PR.

## Known limitations

- **This project shares an AWS account with an unrelated project, and the GitHub OIDC provider is
  worked around rather than isolated.** The IAM OIDC identity provider for GitHub Actions is
  *account-global* - exactly one can exist per URL per AWS account. Account `302954730632` already
  had one, created 2026-05-31 by an earlier `pdm-*` project whose `pdm-github-actions` role still
  trusts it, so the first `terragrunt apply` of `shared/modules/github-oidc` failed outright with
  `EntityAlreadyExists`.

  The fix applied is a `create_oidc_provider` flag on the module: `true` (the default) creates the
  provider so the module still stands alone in a fresh account; `false` - set in
  `terragrunt/vars/shared.tfvars` for this account - adopts the existing one through a read-only
  data source. Importing it instead would have been fewer lines, but would have handed ownership to
  this project's state, so `terragrunt destroy` after the review would have deleted a provider the
  other project depends on.

  **This is a patch, not real isolation.** It solves exactly one collision. Any other account-global
  or fixed-name resource this project might add later (an IAM role or policy name, a Route53 zone, a
  service-linked role) can collide the same way, and the flag doesn't generalise to those. The
  actual fix is **one AWS account per project**, ideally under AWS Organizations so accounts are
  cheap to create and centrally billed - then nothing is shared, `destroy` has a blast radius of
  exactly one project, and no flag is needed. That wasn't done here because there's no existing
  Organization to create a sub-account under, and a brand-new standalone account starts with low
  default EC2/Spot vCPU quotas that would have needed an increase request (hours-to-days turnaround)
  before this stack could launch at all - not viable against the deadline. Given more runway,
  separate accounts is the right answer and this flag should be deleted.

- **NetworkPolicy enforcement is not verified.** The `gitops` repo's default-deny NetworkPolicies
  are what's meant to keep `dev` and `staging` apart on their shared cluster, but nothing in this
  project explicitly enables the VPC CNI's network policy feature - as written, the policies are
  accepted by the API but their real-world enforcement is unconfirmed.
- **TLS is documented, not provisioned.** The Helm chart's ingress annotations include a
  commented-out ACM/HTTPS block; no certificate or DNS is actually set up for this demo.
- **Resource quota sizing** (`gitops/platform/*/resourcequota-*.yaml`) is round numbers picked for
  a demo, not derived from any real workload estimate.
- **Community Terraform module versions are pinned exactly, but a pinned version number doesn't
  guarantee the input schema you remember still matches.** The validation pass on this repo caught
  three real breaking-change mismatches against outdated docs (`terraform-aws-modules/eks/aws`'s
  `cluster_encryption_config`/`cluster_addons`/`eks_managed_node_group_defaults`, and the
  `iam-role-for-service-accounts-eks` submodule rename) that would have failed on the very first
  `terraform init` - re-check the actual tagged source before any future `apply`, not just the
  version number.
- **No CI re-validates this repo automatically.** Unlike `app`'s `actionlint` workflow, nothing
  here re-runs `terraform validate`/`terragrunt hcl validate` on future PRs - it was done locally,
  by hand, each time in this session.
