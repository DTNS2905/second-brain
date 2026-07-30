---
tags:
  - devops
  - github-actions
  - reusable-workflows
  - composite-actions
created: 2026-07-17
source: https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations
---

# GitHub Actions - Reusable Workflows and Composite Actions

> Two mechanisms for sharing pipeline logic. **Reusable workflows** (job-level, multi-job, first-class secrets). **Composite actions** (step-level, single-step-in-caller, no secrets context). Pick per constraint. Back to [[GitHub Actions Guide]].

---

## At-a-Glance

| | Reusable workflow | Composite action |
|---|-------------------|-------------------|
| **Trigger** | `on: workflow_call` | `runs.using: 'composite'` in `action.yml` |
| **Called from** | Caller's `jobs.<x>.uses:` (job level) | Caller's `steps.-.uses:` (step level) |
| **Runs as** | New job(s) on new runner(s) | Bundled steps inside the caller's job |
| **Multiple jobs** | ✅ Yes | ❌ No — always one step in the caller |
| **`secrets` context** | ✅ Full support incl. `secrets: inherit` | ❌ Not available; must pass as inputs |
| **`matrix` strategy** | ✅ Yes | ❌ Not directly (caller can matrix around it) |
| **Location** | `.github/workflows/*.yml` | `action.yml` at repo root or any subdirectory |
| **Nesting depth** | Up to 10 levels; up to 50 unique callees per file | Composites can nest composites (with limits) |

Docs verbatim: reusable workflows *"are called directly within a job, not from a step"* and *"can contain multiple jobs."* Composite actions *"do not contain jobs"* and *"run as a step within a job."*

---

## Reusable Workflows

### Callee — declaring the workflow

```yaml
# .github/workflows/reusable-build.yml
name: Reusable build
on:
  workflow_call:
    inputs:
      node-version:
        type: string
        required: false
        default: '22'
      environment:
        type: string
        required: true
    secrets:
      npm-token:
        required: false
    outputs:
      image-digest:
        description: Digest of the pushed image
        value: ${{ jobs.build.outputs.digest }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.push.outputs.digest }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: actions/setup-node@1d0ff469b7ec7b3cb9d8673fde0c81c44821de2a
        with:
          node-version: ${{ inputs.node-version }}
      - id: push
        run: |
          npm ci && npm run build
          # ...push image, set digest
          echo "digest=sha256:..." >> "$GITHUB_OUTPUT"
```

### Caller — invoking it

```yaml
# .github/workflows/release.yml
jobs:
  build:
    uses: acme/shared/.github/workflows/reusable-build.yml@f6a1c...   # SHA-pinned
    with:
      node-version: '22'
      environment: 'prod'
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}
    # or: secrets: inherit

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying digest ${{ needs.build.outputs.image-digest }}"
```

### Rules and Limits

- **Input types**: `string | boolean | number`. That's it — no `object` / `array`. Serialize JSON via `toJSON()` if needed.
- **`secrets: inherit`** — pass all caller secrets to the callee. Convenient; only use across trust boundaries you own.
- **Permissions inheritance**: docs verbatim: *"The `GITHUB_TOKEN` permissions passed from the caller workflow can be only downgraded (not elevated) by the called workflow."* This holds transitively — nested workflows never elevate above the top caller.
- **Max 50 unique callees** in one workflow file.
- **Up to 10 levels** of nesting.
- **Uses `at job level`** — you *cannot* invoke a reusable workflow inside a step.

### Versioning

`uses: owner/repo/.github/workflows/x.yml@ref` where `ref` is a commit SHA, tag, or branch.

**Recommended**: full-length commit SHA. Prevents someone from retroactively moving a tag to malicious code. Renovate/Dependabot can update SHAs like they do actions.

---

## Composite Actions

### Structure

An `action.yml` at any path; typically at the repo root or under `.github/actions/<name>/`:

```yaml
# .github/actions/setup/action.yml
name: Repo setup
description: Checkout + install deps + hydrate caches
inputs:
  node-version:
    description: Node version
    required: false
    default: '22'
  npm-token:
    description: Publish token (pass explicitly — composite has no secrets context)
    required: false

runs:
  using: 'composite'
  steps:
    - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683

    - uses: actions/setup-node@1d0ff469b7ec7b3cb9d8673fde0c81c44821de2a
      with:
        node-version: ${{ inputs.node-version }}
        cache: 'npm'

    - shell: bash
      run: |
        npm ci
        [ -n "${{ inputs.npm-token }}" ] && npm config set //registry.npmjs.org/:_authToken='${{ inputs.npm-token }}'
```

**Every `run:` step in a composite action must specify a `shell:`.** No default.

### Caller

```yaml
- uses: ./.github/actions/setup             # from same repo
  with:
    node-version: '22'
    npm-token: ${{ secrets.NPM_TOKEN }}      # caller passes secret as input

# or from another repo:
- uses: acme/shared/.github/actions/setup@f6a1c...
```

### The `secrets` gap

Composite actions **do not have access to the `secrets` context**. Docs and GitHub community discussions (#34212, actions/runner #1284/#1557, actions/toolkit #1168) confirm this and note it as a repeatedly requested feature.

Consequence: the caller must pass every secret as an `input`. That input:
- Appears in the composite's `inputs.<name>` (masked in logs, generally).
- Is not automatically masked in the caller's log line that invokes the composite — write the composite invocation carefully.

If your shared logic needs to *read* secrets on its own (e.g., a `secrets: inherit` pattern), use a **reusable workflow** instead.

---

## When to Pick Which

| Situation | Pick |
|-----------|------|
| A bundle of setup steps (checkout, install, cache) | Composite |
| Needs to read secrets on its own | Reusable workflow |
| Needs to run as multiple parallel jobs | Reusable workflow |
| Needs to be a `strategy.matrix` job | Reusable workflow (matrix inside) |
| Should slot cleanly into any job as one step | Composite |
| Should carry its own runners / environments / permissions per job | Reusable workflow |
| Fast local iteration in the same repo | Composite (test in same PR) |

**Rule of thumb**: composites are the equivalent of a shell function; reusable workflows are the equivalent of a program you invoke.

---

## Versioning Both

- **Pin by full-length SHA** in production (`@f6a1c...`).
- Tag major versions with moving tags (`@v3`) so callers can auto-upgrade patch/minor if they choose looseness.
- Dependabot supports both action-uses and reusable-workflow-uses SHA updates.

---

## Cross-Repo Considerations

- Reusable workflows in another repo work as long as the caller has permission to read that repo.
- **Private/internal reusable workflows** in the same org work if the callee repo grants access via the "Access" setting.
- Consuming a callee across the org boundary requires the callee repo to be public or explicitly shared.

---

## Migration Pattern

Common evolution:

1. Copy-paste same 20 lines across 8 workflows → duplicate maintenance burden.
2. Extract to composite action in `.github/actions/setup/` — replaces 20 lines with 3.
3. Later, the composite grows into a multi-job orchestration → convert to reusable workflow.
4. Extract to a shared `acme/shared` repo → org-wide reuse.

Don't skip straight to (4) on day one — the abstraction is easier to design after you know the real variation surface.

---

## Summary

| Question | Answer |
|----------|--------|
| Multi-job needed? | Reusable workflow |
| Reads secrets on its own? | Reusable workflow |
| Just bundles steps? | Composite action |
| Runs as one step in caller's job? | Composite action |
| Runs as a whole new job? | Reusable workflow |
| Version pinning? | Full commit SHA (both kinds) |
| Nesting limit? | 10 levels; 50 unique callees per file (reusable) |
| Permission inheritance? | Can only be downgraded, never elevated |

---

## Related Notes

- [[GitHub Actions - Fundamentals]] — the `workflow_call` event
- [[GitHub Actions - Secrets and OIDC]] — how `secrets: inherit` interacts with OIDC
- [[GitHub Actions - Security Hardening]] — SHA pinning for both actions and reusable workflows
- [[CI-CD - Pipeline Design Patterns]] — abstraction principles for shared pipeline logic
