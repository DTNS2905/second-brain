---
tags:
  - devops
  - github-actions
  - secrets
  - oidc
  - security
created: 2026-07-17
source: https://docs.github.com/en/actions/concepts/security/openid-connect
---

# GitHub Actions - Secrets and OIDC

> Long-lived cloud keys in `secrets.*` are the #1 attack vector on modern GitHub-hosted pipelines. The 2026 default is **OIDC federation** — GitHub mints a short-lived JWT, the cloud provider validates its `sub` claim, temp creds flow back. Back to [[GitHub Actions Guide]].

---

## Secret Scopes

| Scope | Configured at | Used by |
|-------|--------------|---------|
| **Repo secrets** | Repo → Settings → Secrets → Actions | Any workflow in the repo |
| **Environment secrets** | Repo → Settings → Environments → `<env>` → Secrets | Only jobs with `environment: <env>` |
| **Organization secrets** | Org → Settings → Secrets → Actions | Repos in the configured scope (all / private / selected) |

**`secrets` context** — access with `${{ secrets.NAME }}`. Empty string when a secret isn't defined for the current context (useful with `if:` guards).

**`vars` context** — non-secret repo/env/org variables. `${{ vars.NAME }}`. Not masked; use for non-sensitive config (region, feature flags, image names).

---

## Environment Secrets Beat Repo Secrets

Repo secrets are visible to every workflow. Environment secrets are only readable when a job targets that environment (`environment: prod`). Combined with environment protection rules (reviewer approval, wait timer), they give real gates on `PROD_*` credentials.

```yaml
jobs:
  deploy:
    environment: prod                        # unlocks env secrets + protection rules
    steps:
      - run: |
          curl -H "Authorization: Bearer ${{ secrets.PROD_API_TOKEN }}" ...
```

Rule of thumb: production credentials belong on the **prod environment**, not the repo. See [[GitHub Actions - Deployment Environments and Approvals]].

---

## OIDC Federation — Why It Beats Static Keys

Static long-lived cloud key stored in `secrets.AWS_ACCESS_KEY_ID`:
- Visible to every workflow with `secrets: inherit`.
- Rotates rarely; every rotation is a coordinated multi-repo change.
- On leak, valid until manually revoked.

OIDC-federated:
- No long-lived key exists.
- Every job gets a short-lived cloud identity, minted per-run.
- Trust policy binds the cloud role to specific `repo:org/repo:ref` — a fork or unauthorized repo can't assume it.
- Full identity in cloud audit logs (`workflow`, `job`, `actor`, `sha`, `ref`).

---

## The Flow

```
Workflow requests OIDC token from GitHub
  (permissions.id-token: write)
                    │
                    ▼
GitHub returns signed JWT with claims:
  sub: repo:acme/api:ref:refs/heads/main
  aud: sts.amazonaws.com  (or provider-specific)
                    │
                    ▼
Cloud provider validates JWT signature (public key from GitHub)
  and checks trust policy:
    - issuer matches https://token.actions.githubusercontent.com
    - sub matches configured pattern
    - aud matches configured audience
                    │
                    ▼
Cloud provider issues short-lived creds bound to the identity
                    │
                    ▼
Workflow uses creds for the rest of the job
```

Docs verbatim: *"With OIDC, your cloud provider issues a short-lived access token that is only valid for a single job, and then automatically expires... You won't need to duplicate your cloud credentials as long-lived GitHub secrets."*

---

## Required Workflow Permission

```yaml
permissions:
  id-token: write          # MUST be granted — no default
  contents: read
```

Without `id-token: write`, the GitHub OIDC provider will not mint a token. This permission only supports `write | none` (not `read`).

---

## AWS Federation

### One-time setup (in AWS)

1. **Create an OIDC identity provider** in IAM pointing at `token.actions.githubusercontent.com`.
2. **Create an IAM role** whose trust policy conditions on the OIDC issuer + `sub` claim:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:acme/api:ref:refs/heads/main"
    }
  }
}
```

**Only** the `main` branch of `acme/api` can assume this role. Extend `sub` with wildcards or use `StringLike` for finer patterns (`repo:acme/api:environment:prod`, `repo:acme/api:pull_request`, etc.).

### In the workflow

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502
        with:
          role-to-assume: arn:aws:iam::123456789012:role/gha-deploy-api
          aws-region: us-east-1
      - run: aws s3 cp dist/ s3://acme-assets/ --recursive
```

The action reads the OIDC token, calls `sts:AssumeRoleWithWebIdentity`, and exposes `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` (short-lived) as env vars.

---

## GCP Federation (Workload Identity Federation)

1. Create a **Workload Identity Pool** and an **OIDC Provider** in the pool pointing at GitHub.
2. Grant IAM to `principalSet://iam.googleapis.com/projects/.../locations/global/workloadIdentityPools/<pool>/attribute.repository/acme/api` (or narrower attributes).
3. Optionally impersonate a service account.

```yaml
- uses: google-github-actions/auth@71f986410dfbc7added4569d411d040a91dc6935
  with:
    workload_identity_provider: 'projects/123/locations/global/workloadIdentityPools/github/providers/gh'
    service_account: 'gha-deploy@my-project.iam.gserviceaccount.com'
- run: gcloud storage cp -r dist gs://acme-assets/
```

---

## Azure Federation

1. On an **Entra ID app registration** (or user-assigned managed identity), create a **federated credential**:
   - Issuer: `https://token.actions.githubusercontent.com`
   - **Subject**: e.g. `repo:acme/api:environment:prod` — **at least one condition is required**.
   - Audience: `api://AzureADTokenExchange` (default; override for non-public clouds).
2. Assign the app the necessary Azure RBAC roles.

```yaml
- uses: azure/login@a65d910e8af852a8061c627c456678983e180302
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
- run: az account show
```

`AZURE_CLIENT_ID` / `TENANT_ID` / `SUBSCRIPTION_ID` are identifiers, not secrets (per Microsoft docs) — but storing them as secrets is still common and low-cost.

---

## Subject Claim Anatomy

The `sub` claim in the OIDC JWT is what cloud trust policies condition on. Common patterns:

| Pattern | Example `sub` |
|---------|--------------|
| Branch | `repo:acme/api:ref:refs/heads/main` |
| Tag | `repo:acme/api:ref:refs/tags/v1.4.2` |
| PR (any) | `repo:acme/api:pull_request` |
| Environment | `repo:acme/api:environment:prod` |
| Workflow file | `repo:acme/api:job_workflow_ref:acme/api/.github/workflows/deploy.yml@refs/heads/main` |

**Prefer `environment:` subjects for prod.** Requires the job to declare `environment: prod`, which brings environment protection rules along for the ride.

**GitHub April 2026 change**: new repos ship with **immutable `@id`-suffixed subject claims** — the `sub` includes a stable repository ID that doesn't change on rename. Legacy format still valid. Verify your trust patterns against both if you support cross-repo/renamed scenarios.

---

## Vault Integration

For secrets that must be stored (third-party API tokens, DB passwords), federate into your cloud, then pull from a secrets manager:

```yaml
- uses: aws-actions/configure-aws-credentials@...
  with:
    role-to-assume: arn:aws:iam::123:role/gha-ci
    aws-region: us-east-1

- id: secrets
  uses: aws-actions/aws-secretsmanager-get-secrets@...
  with:
    secret-ids: |
      DB_PASS,acme/prod/db
      SLACK_TOKEN,acme/prod/slack

- run: ./deploy.sh          # $DB_PASS and $SLACK_TOKEN in env
```

Equivalents: `hashicorp/vault-action` for Vault, `google-github-actions/get-secretmanager-secrets` for GCP, `Azure/get-keyvault-secrets` for Azure. See [[CI-CD - Secrets Management]].

---

## `secrets: inherit` in Reusable Workflows

```yaml
jobs:
  deploy:
    uses: acme/shared/.github/workflows/reusable-deploy.yml@f6a1c...
    secrets: inherit
```

Passes **all** caller secrets to the callee — convenient for shared workflows in a trusted org boundary, dangerous across trust boundaries. Prefer explicit `secrets:` mapping when the callee only needs a subset:

```yaml
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}
```

See [[GitHub Actions - Reusable Workflows and Composite Actions]].

---

## Log Masking Gotchas

Secrets are auto-masked in logs — but only for the exact value. Encoded / transformed / partial values slip through:

- ✅ `echo "$MY_SECRET"` → `***`
- ❌ `echo "$MY_SECRET" | base64` → un-masked base64
- ❌ Substring of a secret in a URL → un-masked
- ❌ Secret written to a file, then `cat`ed → depends on setup

Add explicit masks in edge cases: `echo "::add-mask::$TRANSFORMED"`.

---

## Summary

| Practice | Effect |
|----------|--------|
| OIDC federation for AWS/GCP/Azure | No long-lived cloud keys in `secrets.*` |
| Environment secrets for prod creds | Gated behind environment protection rules |
| `permissions.id-token: write` | Required to mint an OIDC token |
| Subject claim scoping | Trust bound to exact `repo:org/repo:ref` — forks can't assume |
| `environment:` in subject | Trust bound to environment gate |
| Vaults for non-federatable secrets | Federate into cloud → read from Secrets Manager / Vault |
| `secrets: inherit` sparingly | Only across trust boundaries you own; prefer explicit mapping |
| `add-mask` for transformed secrets | Manual mask when auto-masking misses |

---

## Related Notes

- [[GitHub Actions - Security Hardening]] — the broader security posture
- [[GitHub Actions - Deployment Environments and Approvals]] — environment secrets and protection rules
- [[GitHub Actions - Reusable Workflows and Composite Actions]] — `secrets: inherit` vs explicit
- [[CI-CD - Secrets Management]] — framework-agnostic secrets patterns
