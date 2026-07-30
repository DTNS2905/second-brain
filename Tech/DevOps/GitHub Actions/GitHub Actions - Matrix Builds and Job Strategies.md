---
tags:
  - devops
  - github-actions
  - matrix
  - parallelism
created: 2026-07-17
source: https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow
---

# GitHub Actions - Matrix Builds and Job Strategies

> **Matrix strategy** — one job spec generates N parallel jobs from a table of variable combinations. The idiom for cross-version testing, cross-OS testing, and test sharding. Back to [[GitHub Actions Guide]].

---

## The Cartesian Product

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        node: ['18', '20', '22']
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: actions/setup-node@1d0ff469b7ec7b3cb9d8673fde0c81c44821de2a
        with: { node-version: '${{ matrix.node }}' }
      - run: npm ci && npm test
```

Docs verbatim: *"A job will run for each possible combination of the variables. In this example, the workflow will run six jobs, one for each combination of the os and node values."*

Access matrix values via `${{ matrix.<key> }}`.

---

## `include` — Add or Override

Adds a combination that doesn't fit the base product, or overrides values for one:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
    node: ['20', '22']
    include:
      - os: ubuntu-latest      # add a Windows one-off
        node: '22'
        experimental: true
      - os: windows-latest
        node: '22'
```

Semantics:
- If an `include` entry matches an existing combination (same values for the matrix keys), it **overrides / adds keys** — e.g. adding `experimental: true` to the existing (ubuntu, 22) job.
- If it doesn't match any, it **creates a new job**.

---

## `exclude` — Prune Combinations

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    node: ['18', '20', '22']
    exclude:
      - { os: macos-latest, node: '18' }    # macOS runners can be slow; skip old Node
```

---

## `max-parallel`

Cap concurrent matrix jobs. Useful when downstream infra (external test env, licensed service) can't handle full fan-out:

```yaml
strategy:
  matrix: { shard: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }
  max-parallel: 3
```

10 jobs total; at most 3 run at once.

---

## `fail-fast`

Default `true`: as soon as one matrix job fails, all other **in-progress and queued** matrix jobs are cancelled.

Docs verbatim: *"If any of the jobs with `continue-on-error: false` fail, all jobs that are in progress or queued will be cancelled."*

```yaml
strategy:
  fail-fast: false          # let the rest run — useful for diagnosing which combinations fail
  matrix:
    node: ['18', '20', '22']
    os: [ubuntu-latest, windows-latest]
```

When to disable:
- Broad compatibility testing — you want the full report.
- Flaky environments — one flake shouldn't kill the run.

When to keep enabled:
- PR feedback loops — save runner minutes.
- Shard-and-fail-fast test suites — if shard 3 broke, shards 1/2/4/5 add no info.

---

## `continue-on-error`

Mark a whole matrix combination as non-blocking:

```yaml
strategy:
  matrix:
    node: ['20', '22']
    include:
      - node: 'nightly'
        experimental: true
jobs:
  test:
    continue-on-error: ${{ matrix.experimental || false }}
    ...
```

The `nightly` combination runs, but its failure doesn't fail the workflow. Great for canary tests against unreleased runtimes.

---

## Dynamic Matrices

Compute the matrix in an earlier job, consume it in a later one via `fromJSON`:

```yaml
jobs:
  discover:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set.outputs.matrix }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - id: set
        run: |
          # Enumerate changed packages, or read from a file
          MATRIX=$(ls packages/ | jq -R -s -c 'split("\n") | map(select(length>0))')
          echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"

  test:
    needs: discover
    strategy:
      fail-fast: false
      matrix:
        package: ${{ fromJSON(needs.discover.outputs.matrix) }}
    runs-on: ubuntu-latest
    steps:
      - run: echo "Testing ${{ matrix.package }}"
```

Common uses:
- **Monorepo affected-only** — enumerate packages whose deps changed since `origin/main`.
- **Sharded tests** — output `[1,2,3,...,N]` where N depends on suite size.
- **Environment matrix** — read `environments/*.yml` and run one job per environment.

The `matrix:` value must be a JSON array of scalars or objects. Wrap with `fromJSON()` because job outputs are strings.

---

## Sharding a Test Suite

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        shard: [1, 2, 3, 4, 5]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: actions/setup-node@1d0ff469b7ec7b3cb9d8673fde0c81c44821de2a
        with:
          node-version: '22'
          cache: 'npm'
      - run: npm ci
      - run: npx jest --shard=${{ matrix.shard }}/5 --coverage

  merge-coverage:
    needs: test
    if: ${{ !cancelled() }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@...
        with: { pattern: 'coverage-*', merge-multiple: true, path: coverage }
      - run: npx nyc merge coverage coverage/merged.json
```

5 parallel jobs; a downstream merge job aggregates. `fail-fast: false` because you want the coverage from the passing shards even if one fails. See [[CI-CD - Testing in Pipelines]] for the sharding discussion.

---

## Matrix Contexts

Inside a matrix job, additional contexts are populated:

- `matrix.<key>` — current combination's values.
- `strategy.job-index` — 0-based index of the current job among all combinations.
- `strategy.job-total` — total number of matrix combinations.
- `strategy.fail-fast` — the current setting.
- `strategy.max-parallel` — the current cap.

Useful for naming, dashboards, and passing `--shard=X/N` where X and N come from `strategy`.

---

## Naming Matrix Jobs

By default matrix jobs are named `<job_name> (val1, val2, ...)`. Customize:

```yaml
jobs:
  test:
    name: Test on Node ${{ matrix.node }} / ${{ matrix.os }}
    strategy:
      matrix:
        node: ['20', '22']
        os: [ubuntu-latest, windows-latest]
```

Clean names matter for branch protection — a required check named "Test on Node 22 / ubuntu-latest" is what you reference in required status checks.

---

## Matrix Anti-Patterns

- **Too-wide matrices**: 5 OS × 5 Node × 4 archs × 3 configs = 300 jobs per PR. Burn budget for information you don't act on.
- **Matrix as configuration switch**: if the code path is different per matrix cell (`if: matrix.os == 'windows'`), consider separate jobs instead — clearer intent.
- **Fragile job names in required checks**: renaming a matrix key or a value silently makes required checks stop applying to the new name.
- **Blind sharding**: unshardable state (single DB, single Redis) means all shards fight — actual parallelism is 1.

---

## Summary

| Feature | Semantics |
|---------|-----------|
| `matrix` | Cartesian product of variables → one job per combination |
| `include` | Add or override specific combinations |
| `exclude` | Remove combinations |
| `max-parallel` | Cap simultaneous matrix jobs |
| `fail-fast` (default `true`) | Cancel all matrix jobs on first non-`continue-on-error` failure |
| `continue-on-error: <expr>` | Mark a combination as non-blocking |
| Dynamic matrix | Job output → `fromJSON()` → matrix values |
| `strategy.job-index` / `-total` | Useful for `--shard=X/N` |

---

## Related Notes

- [[GitHub Actions - Workflow Syntax]] — `fromJSON`, `${{ matrix.* }}`, job outputs
- [[GitHub Actions - Caching and Artifacts]] — per-shard artifacts + merge job
- [[CI-CD - Testing in Pipelines]] — sharding rationale, flaky tests, test pyramid
- [[CI-CD - Pipeline Design Patterns]] — fan-out / fan-in
