---
tags:
  - devops
  - github-actions
  - workflows
  - events
  - runners
  - concurrency
created: 2026-07-17
source: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
---

# GitHub Actions - Fundamentals

> Workflow files, events, jobs, steps, runners, and concurrency — the primitives every workflow is made of. Back to [[GitHub Actions Guide]].

---

## Where Workflows Live

`.github/workflows/*.yml` (or `.yaml`). Each file is one workflow. Multiple workflows in a repo can respond to the same event; each runs independently.

Skeleton:

```yaml
name: Descriptive name shown in the Actions tab
on: <event(s)>
permissions: <GITHUB_TOKEN scopes>
concurrency: <group + cancel behavior>
jobs:
  <job_id>:
    runs-on: <runner label>
    steps:
      - <step>
```

---

## Events (Triggers)

The `on:` key lists what fires the workflow.

| Event | Fires when |
|-------|-----------|
| `push` | Commits pushed to a branch or tag |
| `pull_request` | PR opened/updated/reopened (from the *base repo*'s workflow) |
| `pull_request_target` | Same, but runs in the *base repo*'s context with write token — **dangerous with untrusted `checkout`** |
| `schedule` | Cron (`- cron: '0 4 * * *'` — UTC, no per-minute) |
| `workflow_dispatch` | Manual trigger from the UI or API — supports typed `inputs` |
| `workflow_call` | Invoked as a reusable workflow from another workflow |
| `repository_dispatch` | External API call (`POST /repos/{owner}/{repo}/dispatches`) — for webhooks/apps |
| `deployment` / `deployment_status` | Deployment API events |
| `release` | Release created / published / edited |
| `issues` / `issue_comment` / `discussion` / `discussion_comment` | Issue-tracker events |

Filter with `branches` / `tags` / `paths` (and `-ignore` variants):

```yaml
on:
  push:
    branches: [main, 'release/**']
    paths: ['src/**', 'package.json']
    paths-ignore: ['**/*.md']
```

**Multiple events** — array or map. Different filters per event → use the map form.

---

## Jobs

Every job runs on its own runner. Jobs are parallel by default; `needs:` creates a DAG.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps: [...]

  test:
    needs: build           # runs after build succeeds
    runs-on: ubuntu-latest
    steps: [...]

  deploy:
    needs: [build, test]   # fans in
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps: [...]
```

Key job-level keys: `runs-on`, `needs`, `if`, `permissions`, `environment`, `concurrency`, `strategy`, `outputs`, `container`, `services`, `timeout-minutes`, `continue-on-error`.

---

## Steps

Steps run sequentially inside a job, sharing the runner's filesystem.

| Step kind | Syntax |
|-----------|--------|
| Action | `uses: owner/name@ref` |
| Shell command | `run: <script>` |
| Docker action | `uses: docker://<image>` |

Every step has optional `id`, `if`, `name`, `env`, `working-directory`, `continue-on-error`, `timeout-minutes`.

```yaml
steps:
  - name: Checkout
    uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683

  - name: Test
    id: run-tests                       # id required for outputs / referencing
    run: |
      npm ci
      npm test
    env:
      NODE_ENV: test
    working-directory: ./services/api

  - name: Notify only on failure
    if: failure() && github.ref == 'refs/heads/main'
    run: ./scripts/page-oncall.sh
```

---

## Runners

### GitHub-hosted

`runs-on: <label>`:

- `ubuntu-latest` / `ubuntu-24.04` / `ubuntu-22.04` — most common.
- `macos-latest` / `macos-14` (Arm), `macos-14-large` (Intel-arch) — Apple builds.
- `windows-latest` / `windows-2022`.
- **Larger runners** — paid tier with more cores/RAM/GPU/nested-virtualization.
- **ARM64 runners** — `ubuntu-24.04-arm`, `ubuntu-22.04-arm` — now generally available for public and private repos.

Each run gets a fresh VM. State does not persist across jobs (use artifacts or a cache).

### Self-hosted

`runs-on: [self-hosted, linux, x64, gpu]` — matches labels the runner registered with. Use for:
- Access to internal networks / private resources.
- Larger-than-hosted specs (GPUs, huge disks).
- Cost control on high-volume repos.

See [[GitHub Actions - Self-hosted Runners]] for setup, security isolation, ARC on Kubernetes, and autoscaling.

---

## Concurrency Groups

**The single most useful workflow-level control.** Serializes runs in the same group.

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

Docs verbatim: *"Only a single job or workflow using the same concurrency group will run at a time."*

**Default behavior**: a newly queued run in the group **cancels any pending run** in the group. The currently running one keeps going.

**`cancel-in-progress: true`**: extends cancellation to the currently running run too — the new one takes over.

### Common patterns

- **PR runs — cancel superseded pushes:**
  ```yaml
  concurrency:
    group: pr-${{ github.workflow }}-${{ github.event.pull_request.number }}
    cancel-in-progress: true
  ```
- **Prod deploys — serialize, don't cancel:**
  ```yaml
  concurrency:
    group: deploy-prod
    cancel-in-progress: false
  ```
- **Job-scope concurrency** — apply to one job only, not the whole workflow. Useful when only the deploy step needs serialization.

---

## Workflow Permissions (`GITHUB_TOKEN`)

Every job gets a `GITHUB_TOKEN` scoped by `permissions:`. Default depends on org/repo settings — increasingly locked to *read* for `contents` only.

```yaml
permissions:            # workflow-scope
  contents: read
  id-token: write       # needed for OIDC
  packages: write       # needed for GHCR push

jobs:
  narrow-job:
    permissions:        # job-scope overrides workflow-scope
      contents: read
      pull-requests: write
    steps: [...]
```

Scopes accept `read` | `write` | `none`. Shortcut: `permissions: read-all` or `permissions: write-all`. Special: `id-token` only supports `write | none`.

**Always start from `permissions: {}`** and grant what a job actually needs. See [[GitHub Actions - Security Hardening]].

---

## Environments

Attach a job to an environment for protection rules and env-scoped secrets/vars:

```yaml
jobs:
  deploy:
    environment: prod          # or: { name: prod, url: https://api.acme.com }
    steps: [...]
```

Environment rules (configured in repo Settings → Environments) can require reviewers, wait timers, or restrict to specific branches. See [[GitHub Actions - Deployment Environments and Approvals]].

---

## Common Runner Env Vars

| Var | Value |
|-----|-------|
| `GITHUB_WORKSPACE` | Working dir where the repo is checked out |
| `GITHUB_SHA` | Commit SHA that triggered the workflow |
| `GITHUB_REF` | `refs/heads/main`, `refs/tags/v1.0.0`, `refs/pull/42/merge`, etc. |
| `GITHUB_REPOSITORY` | `owner/repo` |
| `GITHUB_ACTOR` | User or app that triggered the run |
| `GITHUB_EVENT_NAME` | The event that triggered (`push`, `pull_request`, ...) |
| `RUNNER_OS` / `RUNNER_ARCH` | `Linux` / `X64`, etc. |
| `GITHUB_OUTPUT` | Path to write step outputs |
| `GITHUB_ENV` | Path to write env vars for later steps |
| `GITHUB_STEP_SUMMARY` | Markdown file rendered under the job on the summary page |

Access in expressions as `${{ github.sha }}`, `${{ runner.os }}`, etc. (the `env` context does not include runner-inherited vars — see [[GitHub Actions - Workflow Syntax]]).

---

## Summary

| Primitive | Key knobs |
|-----------|----------|
| Workflow file | `.github/workflows/*.yml`; one workflow per file |
| Events | `push`, `pull_request`, `schedule`, `workflow_dispatch`, `workflow_call`, `repository_dispatch` |
| Jobs | Parallel by default; `needs:` builds a DAG; each gets a fresh runner |
| Steps | `uses:` (action) or `run:` (shell); require `id` for outputs |
| Runner | `runs-on: ubuntu-latest` (hosted) or `[self-hosted, ...labels]` |
| Concurrency | `group:` + `cancel-in-progress:`; workflow- or job-scoped |
| Permissions | `permissions:` per scope; start from `{}`; downgrade-only in reusable calls |
| Environments | Attach with `environment: prod`; unlock protection rules and env secrets |

---

## Related Notes

- [[GitHub Actions - Workflow Syntax]] — expressions, contexts, conditionals, outputs
- [[GitHub Actions - Reusable Workflows and Composite Actions]] — the `workflow_call` event
- [[GitHub Actions - Self-hosted Runners]] — running your own machines
- [[GitHub Actions - Security Hardening]] — `GITHUB_TOKEN`, SHA pinning, `pull_request_target`
