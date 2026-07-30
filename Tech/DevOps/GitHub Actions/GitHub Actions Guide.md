---
tags:
  - devops
  - github-actions
  - ci-cd
  - workflows
created: 2026-07-17
source: https://docs.github.com/en/actions
---

# GitHub Actions Guide

> **GitHub Actions** — GitHub's built-in workflow engine. Free for public repos, generous free tier for private, dominant in the 2026 open-source ecosystem. This note set is the concrete GitHub Actions expression of the ideas in [[CI-CD Guide]]. Part of [[DevOps Guide]].

---

## Contents

| Note | Covers |
|------|--------|
| [[GitHub Actions - Fundamentals]] | Workflow files, events/triggers, jobs, steps, runners (GitHub-hosted vs self-hosted), concurrency groups |
| [[GitHub Actions - Workflow Syntax]] | `${{ }}` expressions, 12 contexts, `if:` conditionals, `env` vs shell vars, `$GITHUB_ENV`, step and job outputs |
| [[GitHub Actions - Reusable Workflows and Composite Actions]] | `workflow_call` vs composite `action.yml`, inputs/outputs/secrets, when to pick which, versioning |
| [[GitHub Actions - Matrix Builds and Job Strategies]] | Multi-dim matrix, `include`/`exclude`, `max-parallel`, `fail-fast`, dynamic matrices |
| [[GitHub Actions - Caching and Artifacts]] | `actions/cache` (key/restore-keys), upload/download-artifact v4, `setup-*` built-in caches, Docker `type=gha` |
| [[GitHub Actions - Secrets and OIDC]] | Repo/env/org secrets, OIDC federation to AWS/GCP/Azure, `permissions.id-token`, subject claim scoping |
| [[GitHub Actions - Self-hosted Runners]] | Setup, runner groups, ephemeral runners, Actions Runner Controller (ARC) on Kubernetes, autoscaling |
| [[GitHub Actions - Security Hardening]] | SHA-pinned actions, `GITHUB_TOKEN` permissions, `pull_request_target` risk, script injection, StepSecurity, Scorecard |
| [[GitHub Actions - Deployment Environments and Approvals]] | Environment protection rules, required reviewers, wait timers, deployment gates, environment secrets |

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **Workflow** | A YAML file under `.github/workflows/` triggered by events. |
| **Event** | What triggers a workflow: `push`, `pull_request`, `schedule`, `workflow_dispatch`, `workflow_call`, `repository_dispatch`, etc. |
| **Job** | A group of steps that run on one runner. Jobs default to running in parallel; use `needs:` to serialize. |
| **Step** | A single unit within a job — either a `run:` shell command or a `uses:` action. |
| **Runner** | The machine that executes a job — GitHub-hosted (`ubuntu-latest`, etc.) or self-hosted. |
| **Action** | A reusable unit invoked via `uses: owner/name@ref`. JavaScript, Docker, or composite. |
| **Reusable workflow** | A workflow with `on: workflow_call` invoked by another workflow's `uses:` at the job level. |
| **Composite action** | An action defined as a bundle of steps, invoked as a step (`uses:`). No jobs, no secrets context. |
| **Context** | Named object accessible in expressions: `github`, `env`, `vars`, `secrets`, `needs`, `matrix`, `job`, `steps`, `runner`, `strategy`, `inputs`, `jobs`. |
| **Runner group** | Scoping construct for self-hosted runners — which repos/orgs can use them. |
| **Environment** | A deployment target with protection rules, secrets, and vars — e.g. `staging`, `prod`. |
| **`GITHUB_TOKEN`** | An auto-generated per-job token; permissions declared with `permissions:` at workflow or job scope. |

---

## Mental Model

```
Event (push, PR, cron, dispatch) ──▶ Workflow(s) ──▶ Job(s) ──▶ Step(s) on a Runner
                                        │              │
                                        │              └─ uses: (action) OR run: (shell)
                                        │
                                        └─ needs: (DAG), if: (conditional), strategy.matrix: (fan-out)
```

- Multiple workflows can respond to one event.
- Multiple jobs run in parallel by default; `needs:` builds a DAG.
- Each job gets a fresh runner (fresh disk, fresh env) unless self-hosted with non-ephemeral setup.

---

## The 2026 Baseline

1. **OIDC federation, not long-lived cloud keys.** Set `permissions.id-token: write`; use `aws-actions/configure-aws-credentials`, `google-github-actions/auth`, or `azure/login`. → [[GitHub Actions - Secrets and OIDC]]
2. **Pin third-party actions by full-length SHA**, not tag. Dependabot updates the SHAs. → [[GitHub Actions - Security Hardening]]
3. **Restrict `GITHUB_TOKEN`.** Default your workflow to `permissions: {}`; grant per-scope only what a job needs.
4. **Concurrency groups.** Cancel superseded PR runs; serialize prod deploys.
5. **Reusable workflows for org-wide patterns.** Composite actions for step bundles without secrets. → [[GitHub Actions - Reusable Workflows and Composite Actions]]
6. **Environments for prod.** Required reviewers, wait timers, and environment-scoped secrets — real gates on real deploys. → [[GitHub Actions - Deployment Environments and Approvals]]
7. **Cache aggressively** (`setup-*` built-in cache flags, `actions/cache` with lockfile-hashed keys). → [[GitHub Actions - Caching and Artifacts]]
8. **Never `pull_request_target` with untrusted `checkout`.** Highest-impact supply-chain footgun. → [[GitHub Actions - Security Hardening]]

---

## Minimal Workflow

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push: { branches: [main] }
  pull_request:

permissions:
  contents: read     # least privilege by default

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683   # v4.2.2
      - uses: actions/setup-node@1d0ff469b7ec7b3cb9d8673fde0c81c44821de2a  # v4.2.0
        with:
          node-version: '22'
          cache: 'npm'
      - run: npm ci
      - run: npm test
```

Every rule in the 2026 baseline is visible here: least-privilege `permissions`, `concurrency.cancel-in-progress`, SHA-pinned actions, `setup-node` built-in cache.

---

## Related — Not Covered

- **GitHub Actions marketplace ecosystem** — how to evaluate a third-party action's security posture (see [[GitHub Actions - Security Hardening]] for principles).
- **GitHub Enterprise Server / Cloud differences** — most notes assume Cloud; ES has some API/version drift.
- **Alternatives**: GitLab CI, CircleCI, Jenkins, Buildkite — the CI/CD ideas are portable (see [[CI-CD Guide]]).

---

## Related Notes

- [[DevOps Guide]] — parent index
- [[CI-CD Guide]] — framework-agnostic principles these notes instantiate
- [[Docker Guide]] — the artifact GitHub Actions typically builds and ships
