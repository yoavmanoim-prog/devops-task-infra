# Architecture

```mermaid
flowchart TB
    subgraph GitHub["GitHub (3 repos)"]
        InfraRepo["devops-task-infra<br/>Terraform + Terragrunt"]
        GitopsRepo["devops-task-gitops<br/>Helm chart + ArgoCD manifests"]
        AppRepo["devops-task-app<br/>FastAPI + CI/CD"]
    end

    subgraph AWS["AWS account 302954730632 (us-east-1)"]
        OIDC["IAM OIDC provider<br/>+ github-actions role"]
        ECR["ECR<br/>devops-task-app<br/>(IMMUTABLE tags)"]

        subgraph DevCluster["EKS: dev cluster"]
            DevArgo["ArgoCD"]
            DevNS["ns: dev"]
            StagingNS["ns: staging"]
        end

        subgraph ProdCluster["EKS: prod cluster"]
            ProdArgo["ArgoCD"]
            ProdNS["ns: production"]
        end
    end

    InfraRepo -- "terragrunt apply" --> AWS
    InfraRepo -. "provisions cluster,<br/>controllers, ArgoCD,<br/>one bootstrap Application" .-> DevArgo
    InfraRepo -. "same, per env" .-> ProdArgo

    AppRepo -- "OIDC-assume role" --> OIDC
    AppRepo -- "push sha-&lt;shortsha&gt; image" --> ECR
    AppRepo -- "bump image tag<br/>(commit + push)" --> GitopsRepo

    GitopsRepo -- "watched by" --> DevArgo
    GitopsRepo -- "watched by" --> ProdArgo

    DevArgo -- "ApplicationSet<br/>(auto-sync)" --> DevNS
    DevArgo -- "ApplicationSet<br/>(auto-sync)" --> StagingNS
    ProdArgo -- "Application<br/>(manual sync)" --> ProdNS

    DevNS -- "pulls image" --> ECR
    StagingNS -- "pulls image" --> ECR
    ProdNS -- "pulls image" --> ECR
```

**Promotion flow**: a push to `app`'s `dev` branch builds once, smoke-tests the container, pushes
one immutable tag to ECR, then bumps that tag into `gitops/apps/dev/values-dev.yaml` - ArgoCD's
ApplicationSet on the dev cluster picks it up automatically. Merging `dev` → `staging` (a PR within
`app`) re-tags the *same* image into `apps/dev/values-staging.yaml`, no rebuild. Merging
`staging` → `prod` does the same into `apps/prod/values-production.yaml`, but production's
`Application` has no automated sync policy - the tag lands in git immediately, but a human still
clicks Sync in ArgoCD before it actually deploys.
