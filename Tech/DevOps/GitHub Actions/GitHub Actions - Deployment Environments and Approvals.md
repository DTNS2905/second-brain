---
tags:
  - devops
  - github-actions
  - environments
  - deployment
  - approvals
created: 2026-07-17
source: https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment
---

# GitHub Actions - Deployment Environments and Approvals

> **Environments** — first-class deployment targets with protection rules, environment-scoped secrets/vars, and deployment tracking. The right home for `PROD_*` credentials and reviewer gates. Back to [[GitHub Actions Guide]].

---

## What an Environment Gives You

Attach a job to an environment:

```yaml
jobs:
  deploy-prod:
    environment:
      name: prod
      url: https://api.acme.com
    runs-on: ubuntu-latest
    steps: [...]
```

Unlocks:

- **Environment secrets and variables** — scoped to jobs that target this env.
- **Protection rules** — required reviewers, wait timer, allowed branches/tags, custom gates.
- **URL badge** — the "View deployment" link in the PR/commit UI.
- **Deployment tracking** — the deploy is recorded against the environment; visible in Insights and the API.

Environments are configured in Repo → Settings → Environments → New environment.

---

## Protection Rules

### Required Reviewers

Up to 6 named users or teams. The job **pauses in the "Waiting"** state until an approver clicks approve. Denials cancel the job.

- Common pattern: `sre` team, on-call rotation, `security` team for prod.
- Approver **can** be the person who triggered the workflow (unless "Prevent self-review" is enabled).

### Wait Timer

Force a delay (0–43,200 min = 30 days) between the job being ready and starting to run. Use cases:
- Cooling-off period between staging and prod deploys.
- Time for automated monitoring to catch obvious regressions in the earlier environment.

### Deployment Branch and Tag Rules

Restrict which refs can deploy to this environment:
- **All branches** (default).
- **Protected branches** — only branches with branch protection rules.
- **Selected branches and tags** — glob patterns like `main`, `release/*`, `v*`.

For `prod`, typical: only `main` and tags matching `v*`.

### Custom Deployment Protection Rules (Deployment Gates)

Third-party (or self-built) apps can register as deployment gates. Examples:
- **ServiceNow** — approval workflow inside SN.
- **Datadog** — pause the deploy until an SLO check passes.
- **Change management systems** — validate a change ticket exists and is approved.

Runs pause at the gate; the app calls the deployment protection rules API to approve or reject. Powerful but requires the app to exist.

---

## Environment Secrets vs Repo Secrets

| | Repo secrets | Environment secrets |
|---|-------------|---------------------|
| Visible to | Every workflow | Only jobs with `environment: <env>` |
| Best for | CI-only creds (e.g. Codecov token) | Production creds gated by protection rules |
| Protection | None beyond `permissions:` and branch protection | Environment rules apply |

**Move all `PROD_*` secrets to the `prod` environment.** A workflow that doesn't target `prod` can't see them, even if it inherits repo secrets.

---

## Typical Environment Setup

For most teams, three environments — pattern the whole deploy pipeline around them:

| Environment | Protection rules |
|-------------|------------------|
| `dev` | None (or auto-deploy from a `dev` branch). Fast iteration. |
| `staging` | Restrict to `main`. No reviewers. Wait timer optional. |
| `prod` | Restrict to `main`. Required reviewers: SRE + on-call. Wait timer 5–15 min. Custom gate for Datadog SLO check. |

```yaml
jobs:
  deploy-staging:
    environment: staging
    steps: [...]

  smoke-staging:
    needs: deploy-staging
    steps: [...]

  deploy-prod:
    needs: smoke-staging
    environment:
      name: prod
      url: https://api.acme.com
    steps: [...]
```

Green pipeline through staging → smoke tests → prod job **waits for review** → deploy → post-deploy verification.

---

## OIDC + Environments: The Combined Pattern

Environments + OIDC together give you real least-privilege prod deploys:

```yaml
jobs:
  deploy-prod:
    environment: prod
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502
        with:
          role-to-assume: arn:aws:iam::123:role/gha-prod-deploy
          aws-region: us-east-1
      - run: ./deploy.sh
```

The AWS role's trust policy conditions on `sub: repo:acme/api:environment:prod`. Combined:
1. Only workflows on the `main` branch (env branch rule) can even start the job.
2. Job pauses for reviewer approval (env rule).
3. Only when running the `prod` environment can the AWS role be assumed (OIDC trust).
4. Creds are short-lived, scoped to this deploy.

A leaked repo secret, a mistargeted workflow, or a compromised action all fail one of the four checks.

---

## Deployment API

Every job with `environment:` creates a **deployment** and updates its **deployment status** automatically. You get:

- `GET /repos/{owner}/{repo}/deployments` — history.
- `GET /repos/{owner}/{repo}/environments/{env}` — env details.
- `POST /repos/{owner}/{repo}/deployments/{id}/statuses` — post extra statuses (post-deploy verify, canary metrics).

Third-party tools (Datadog, Sleuth, LinearB) consume this API to compute DORA metrics automatically. See [[CI-CD - Observability and Rollback]].

---

## Manual Deploys via `workflow_dispatch`

For "human triggers the deploy" — deploy a specific SHA, deploy to a specific env — combine `workflow_dispatch` + `environment`:

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        type: environment
        required: true
      sha:
        type: string
        required: true

jobs:
  deploy:
    environment: ${{ inputs.environment }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with: { ref: ${{ inputs.sha }} }
      - run: ./deploy.sh
```

The `type: environment` input renders as a dropdown in the UI populated from repo environments. Combined with `environment: ${{ inputs.environment }}`, the deploy uses the selected env's protection rules and secrets automatically.

---

## Marking a Deploy

For dashboards / observability, emit a **deploy marker** as the last step:

```yaml
- name: Datadog deploy event
  if: success()
  run: |
    curl -X POST "https://api.datadoghq.com/api/v1/events" \
      -H "DD-API-KEY: ${{ secrets.DATADOG_API_KEY }}" \
      -H "Content-Type: application/json" \
      -d '{
        "title": "Deploy: api ${{ github.sha }} to prod",
        "text":  "Deployed by ${{ github.actor }} via ${{ github.workflow }}",
        "tags":  ["env:prod","service:api","git_sha:${{ github.sha }}"],
        "alert_type": "info"
      }'
```

Every dashboard should carry these markers. See [[CI-CD - Observability and Rollback]] for the strategic case.

---

## Combining with Branch Protection

Environment rules gate the deploy job specifically. **Branch protection** (Repo → Settings → Rules) gates what can even land on the branch that triggers the deploy:

- Required PR review.
- Required status checks (matrix job names, CodeQL, dependency review).
- Required signed commits.
- Merge queue.

Prod deploys are safest when both are in play: branch protection ensures only reviewed code lands on `main`; environment protection ensures only reviewed deploys of that code reach `prod`.

---

## Common Anti-Patterns

- ❌ Storing `PROD_*` secrets as repo secrets. Move to env.
- ❌ Auto-deploying to prod on `push: main` with no reviewer gate. Even in a fast-shipping culture, environments enable one-click promotion instead of automatic.
- ❌ `prod` environment allowing all branches. Restrict to `main` (+ release tags).
- ❌ Required reviewer = "one team of 30 people" — nobody feels ownership. Fewer, named reviewers.
- ❌ Wait timer on `prod` as the only rollback mechanism. Wait timers help catch obvious regressions but aren't a substitute for canary + automated rollback.

---

## Summary

| Feature | Use |
|---------|-----|
| `environment:` in a job | Unlock env secrets/vars, protection rules, deploy tracking |
| Required reviewers | Human gate before prod deploy runs |
| Wait timer | Cooling-off window between environments |
| Branch/tag rules | Only `main` + release tags reach `prod` |
| Custom deployment gates | Datadog SLO check, ServiceNow ticket, etc. |
| Environment secrets | Scope prod creds to prod-targeted jobs |
| OIDC `environment:` subject claim | Cloud role assumable only from the prod environment |
| Deployment API + markers | Feed DORA dashboards and observability |
| Branch protection alongside | Guards what lands; env guards what deploys |

---

## Related Notes

- [[GitHub Actions - Secrets and OIDC]] — env-subject OIDC federation
- [[GitHub Actions - Security Hardening]] — the wider hardening story
- [[CI-CD - Deployment Strategies]] — canary + reviewer gates + rollback
- [[CI-CD - Observability and Rollback]] — deploy markers and DORA metrics
- [[Docker - Production Considerations]] — GitOps flow, prod-tag discipline
