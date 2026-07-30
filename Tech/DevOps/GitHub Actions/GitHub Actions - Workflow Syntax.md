---
tags:
  - devops
  - github-actions
  - expressions
  - contexts
  - syntax
created: 2026-07-17
source: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
---

# GitHub Actions - Workflow Syntax

> Expressions, the 12 contexts, `if:` conditionals, env vars, and step/job outputs — the language YAML workflows are actually written in. Back to [[GitHub Actions Guide]].

---

## Expressions: `${{ ... }}`

Anywhere inside a workflow YAML, `${{ expression }}` is evaluated by the runner:

```yaml
run: echo "Deploying ${{ github.sha }} to ${{ inputs.env }}"
if:  ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}
```

**String literals must use single quotes**. Double quotes are a syntax error inside expressions:

```yaml
✅ if: github.ref == 'refs/heads/main'
❌ if: github.ref == "refs/heads/main"   # error
```

Escape a literal single quote by doubling it: `'don''t'`.

Property access supports both dot and bracket forms:
- `github.event.pull_request.number`
- `github['event']['pull_request']['number']` — required when the key contains a hyphen or starts with a digit.

---

## The 12 Contexts

Every context is a named object exposed inside `${{ }}`:

| Context | What it contains |
|---------|-----------------|
| `github` | Event payload, `sha`, `ref`, `workspace`, `actor`, `event_name`, `repository`, `run_id`, `run_number`, etc. |
| `env` | Env vars set at workflow/job/step scope — **not** runner-inherited env vars |
| `vars` | Repo/env/org **variables** (non-secret) |
| `secrets` | Repo/env/org **secrets** — masked in logs |
| `needs` | Outputs and result of jobs listed in `needs:` |
| `matrix` | Matrix variables for the current combination |
| `strategy` | The current job's matrix strategy info (`job-index`, `fail-fast`, etc.) |
| `job` | Info about the current job (`status`, `container`, `services`) |
| `jobs` | (Reusable workflows only) all jobs' outputs — used in `workflow_call.outputs` |
| `steps` | Outputs of previous steps in this job that had an `id` |
| `runner` | Runner info: `os`, `arch`, `name`, `temp`, `tool_cache` |
| `inputs` | Inputs for `workflow_call`, `workflow_dispatch`, composite actions |

**Availability matters** — each context is only available in certain places. `secrets` is not accessible in composite actions. `needs` is not available before dependency resolution. See the [Context availability](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts) table for the full grid.

---

## `env` Context vs Shell Vars

Two different worlds. Docs verbatim: *"The env context contains variables that have been set in a workflow, job, or step. It does not contain variables inherited by the runner process."*

```yaml
env:
  MODE: production            # workflow scope

jobs:
  demo:
    env:
      MODE: staging            # job scope overrides
    steps:
      - name: See both
        env:
          MODE: step-only     # step scope overrides again
        run: |
          echo "Expression: ${{ env.MODE }}"        # 'step-only'
          echo "Shell     : $MODE"                    # 'step-only'
          echo "Runner var : $HOME"                    # /home/runner — not visible via env context
```

`${{ env.HOME }}` returns nothing. `$HOME` works. Rule: `${{ env.X }}` sees only what YAML declared; `$X` sees anything the runner shell can.

---

## `$GITHUB_ENV` — Setting env for Later Steps

Append `NAME=value` lines to the `$GITHUB_ENV` file to expose an env var to subsequent steps in the same job:

```yaml
- name: Compute build tag
  run: |
    TAG="git-$(git rev-parse --short HEAD)-$(date +%s)"
    echo "BUILD_TAG=$TAG" >> "$GITHUB_ENV"

- name: Use it
  run: echo "Built $BUILD_TAG"
  # $BUILD_TAG is now in the shell env; ${{ env.BUILD_TAG }} also works
```

Multi-line values use a heredoc-style block:

```yaml
run: |
  {
    echo 'CHANGELOG<<EOF'
    cat CHANGELOG.md
    echo EOF
  } >> "$GITHUB_ENV"
```

---

## Step and Job Outputs

### Step outputs (within one job)

Set with `$GITHUB_OUTPUT`; read with `steps.<id>.outputs.<name>`:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - id: version
        run: |
          V=$(cat VERSION)
          echo "version=$V" >> "$GITHUB_OUTPUT"

      - name: Use it
        run: echo "Version is ${{ steps.version.outputs.version }}"
```

The setting step needs an `id`. Values are strings — serialize JSON if you need structure.

### Job outputs (between jobs)

Declared at the job level, read via `needs.<job_id>.outputs.<name>`:

```yaml
jobs:
  compute:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.v.outputs.version }}
      matrix:  ${{ steps.m.outputs.matrix }}
    steps:
      - id: v
        run: echo "version=1.4.2" >> "$GITHUB_OUTPUT"
      - id: m
        run: echo 'matrix=["18","20","22"]' >> "$GITHUB_OUTPUT"

  test:
    needs: compute
    strategy:
      matrix:
        node: ${{ fromJSON(needs.compute.outputs.matrix) }}
    steps:
      - run: echo "Node ${{ matrix.node }} for v${{ needs.compute.outputs.version }}"
```

Dynamic matrices are one of the killer features enabled by this pattern — see [[GitHub Actions - Matrix Builds and Job Strategies]].

---

## Conditionals with `if:`

`if:` runs the step or job only when the expression is truthy.

```yaml
if: github.event_name == 'push'
if: github.ref == 'refs/heads/main' && success()
if: startsWith(github.ref, 'refs/tags/v')
if: contains(fromJSON('["push","workflow_dispatch"]'), github.event_name)
```

`if:` outside `${{ }}` also works — GitHub evaluates it as an expression automatically. Both forms are accepted; the bare form is cleaner.

### Status check functions

| Function | True when |
|----------|-----------|
| `success()` | All previous steps succeeded (default `if`) |
| `failure()` | Any previous step failed |
| `cancelled()` | Workflow was cancelled |
| `always()` | Always runs — even on cancel |
| `!cancelled()` | Runs on success or failure, honors cancel |

**Prefer `!cancelled()` over `always()` for cleanup.** Docs: *"Avoid using always for any task that could suffer from a critical failure, for example: getting sources, otherwise the workflow may hang until it times out."* `always()`-guarded steps aren't cancellable.

```yaml
- name: Publish test report
  if: ${{ !cancelled() }}       # runs on pass or fail; still cancellable
  uses: dorny/test-reporter@...
```

---

## Useful Expression Functions

| Function | Use |
|----------|-----|
| `contains(list_or_string, item)` | Substring / element check |
| `startsWith(str, prefix)` / `endsWith(str, suffix)` | Prefix / suffix |
| `format('{0}-{1}', a, b)` | String interpolation with positional placeholders |
| `join(array, separator)` | Array → string |
| `toJSON(value)` / `fromJSON(string)` | Serialize / parse JSON — essential for dynamic matrices |
| `hashFiles(<glob>)` | SHA-256-of-hashes over matching files — canonical cache key |
| `success()` / `failure()` / `cancelled()` / `always()` | Job/step status predicates |

`hashFiles('**/package-lock.json')` is the standard primary cache key for JS projects — see [[GitHub Actions - Caching and Artifacts]].

---

## Escaping and Multi-Line Strings

- YAML block scalars: `|` preserves newlines, `>` folds them. Almost always use `|` for `run:`.
- Backslash escapes in single-line `run:` — treat as shell.
- Expressions inside `run:` block are evaluated *before* the shell sees the script — so quote them if the value could contain spaces:
  ```yaml
  run: echo "${{ github.event.head_commit.message }}"     # good — expression is quoted
  run: echo ${{ github.event.head_commit.message }}       # dangerous — words split
  ```

**Warning**: unsanitized expression interpolation into `run:` is one of the main script-injection vectors. See [[GitHub Actions - Security Hardening]].

---

## Reserved and Special Names

- Env var names starting with `GITHUB_` or `RUNNER_` are reserved.
- `github.event_name`, `github.event.action`, `github.event.pull_request.number` are event-shape-dependent — check the docs for the specific event.
- Boolean-looking strings (`'true'`, `'false'`) are strings unless parsed with `fromJSON`.

---

## Summary

| Feature | Key rule |
|---------|---------|
| `${{ ... }}` expressions | Single-quoted strings only; double quotes throw |
| 12 contexts | `github`, `env`, `vars`, `secrets`, `needs`, `matrix`, `strategy`, `job`, `jobs`, `steps`, `runner`, `inputs` |
| `env` context vs shell | Only sees what YAML declared; shell sees runner-inherited too |
| `$GITHUB_ENV` | Set env vars for subsequent steps in the same job |
| `$GITHUB_OUTPUT` | Set step outputs, read via `steps.<id>.outputs.<name>` |
| Job outputs | Declared at job level; read via `needs.<id>.outputs.<name>` |
| `if:` guards | Bare form allowed; `!cancelled()` beats `always()` for cleanup |
| `hashFiles()` | Canonical cache key generator |
| `fromJSON(...)` | Parse dynamic matrix outputs, structured values |
| Script injection | Never interpolate untrusted expressions directly into `run:` |

---

## Related Notes

- [[GitHub Actions - Fundamentals]] — workflow structure, events, jobs, runners
- [[GitHub Actions - Matrix Builds and Job Strategies]] — matrices consuming job outputs
- [[GitHub Actions - Caching and Artifacts]] — `hashFiles()` in real use
- [[GitHub Actions - Security Hardening]] — script injection via expressions
